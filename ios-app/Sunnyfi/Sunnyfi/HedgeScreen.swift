//
//  HedgeScreen.swift
//  Sunnyfi
//
//  Phase 1 of the Hedge tab. Top-down:
//   • Freshness pill — when greeks were last pulled, refresh cadence
//   • Period toggle (DAY default, WEEK preview)
//   • DAY view:
//       – Portfolio θ hero (today only, no day-over-day yet)
//       – Cliff watch (only if any leg ≥ CLIFF)
//       – Per-ticker cards with zone gauges
//   • WEEK view:
//       – This-week progress bar (today's θ × 5 vs short-call credits)
//       – Per-ticker weekly aggregates
//
//  Phase 2 will add the 14-day sparkline + day-over-day Δ-change once
//  the daily_theta_snapshot table is in place. Phase 3 adds prior-week
//  history. Phase 4 adds the SPY stress slider.
//

import SwiftUI

struct HedgeScreen: View {
    let store: PortfolioStore
    let auth: AuthStore

    enum Period: String, CaseIterable, Identifiable {
        case day = "DAY", week = "WEEK"
        var id: String { rawValue }
    }
    @State private var period: Period = .day
    /// Ticker tapped on a per-ticker card → opens the existing modal.
    @State private var sheetTicker: String? = nil
    /// Zone filter for the per-ticker section. "+" semantics: WATCH+
    /// shows WATCH and worse; CRITICAL is exact (already worst).
    @State private var zoneFilter: ZoneFilter = .all

    enum ZoneFilter: Hashable {
        case all
        case watchPlus
        case cliffPlus
        case criticalOnly

        var label: String {
            switch self {
            case .all:          return "ALL"
            case .watchPlus:    return "WATCH+"
            case .cliffPlus:    return "CLIFF+"
            case .criticalOnly: return "CRITICAL"
            }
        }

        /// Color tint for the chip.
        var tint: Color {
            switch self {
            case .all:          return Color.theme.fg2
            case .watchPlus:    return Color.theme.fg2
            case .cliffPlus:    return Color.theme.warn
            case .criticalOnly: return Color.theme.neg
            }
        }

        func includes(_ z: HedgeZone) -> Bool {
            switch self {
            case .all:          return true
            case .watchPlus:    return z >= .watch
            case .cliffPlus:    return z >= .cliff
            case .criticalOnly: return z == .critical
            }
        }
    }

    private var snap: HedgeTodaySnapshot { store.hedgeToday }
    /// Live-vs-snapshot day-over-day Δ. Hero animates as state changes.
    private var dayDelta: HedgeDayDelta {
        HedgeHistory.dayDelta(liveBurn: snap.totalBurn, snapshots: store.dailyTheta)
    }
    /// 14-day sparkline data, today is appended live.
    private var sparkline: [SparklinePoint] {
        HedgeHistory.sparkline(liveBurn: snap.totalBurn, snapshots: store.dailyTheta)
    }
    /// Last 4 complete weeks for the WEEK view history strip.
    private var priorWeeks: [PriorWeekSummary] {
        HedgeHistory.priorWeeks(snapshots: store.dailyTheta, trades: store.allTrades)
    }

    /// Per-ticker groups filtered by the active zone chip. Tickers whose
    /// remaining legs become empty after the filter are dropped.
    private var filteredTickerGroups: [(ticker: String, legs: [HedgeLegLive])] {
        snap.byTicker
            .map { (ticker: $0.ticker, legs: $0.legs.filter { zoneFilter.includes($0.zone) }) }
            .filter { !$0.legs.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleRow
                periodToggle
                if snap.isEmpty {
                    emptyCard
                } else if period == .day {
                    dayView
                } else {
                    weekView
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 100)   // floating tab bar clearance
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.theme.page.ignoresSafeArea())
        .sheet(item: Binding(
            get: { sheetTicker.map { IdentifiedString(value: $0) } },
            set: { sheetTicker = $0?.value }
        )) { id in
            TickerTradesSheet(store: store, ticker: id.value, initialTab: .lots)
        }
    }

    // ── Title ──
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Hedge")
                .heroTitle()
            Spacer()
            if !snap.isEmpty {
                Text("\(snap.legs.count) open put\(snap.legs.count == 1 ? "" : "s")")
                    .font(.numeric(size: 12, weight: .semibold))
                    .foregroundStyle(Color.theme.fg3)
            }
        }
    }

    // ── Empty state ──
    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BOOK UNHEDGED")
                .font(.ui(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.theme.fg3)
            Text("No open long puts. Theta isn't bleeding you today.")
                .font(.ui(size: 13, weight: .medium))
                .foregroundStyle(Color.theme.fg2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .navCard(stroke: Color.theme.neon.opacity(0.18))
    }

    // ── Freshness pill ──
    //
    // The greeks feed updates every 15m during US market hours (Mon–Fri
    // 9:00–15:00 EST) via the mp-refresh-15min cron. We show how long
    // since the last capture; outside market hours we add a hint that
    // the cron is paused.
    private var freshnessPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(freshnessColor)
                .frame(width: 6, height: 6)
            Text(freshnessText)
                .font(.numeric(size: 11, weight: .semibold))
                .foregroundStyle(Color.theme.fg2)
            if let next = nextRefreshHint {
                Text("·")
                    .foregroundStyle(Color.theme.fg4)
                Text(next)
                    .font(.numeric(size: 11, weight: .medium))
                    .foregroundStyle(Color.theme.fg3)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular.tint(Color.theme.page2.opacity(0.5)), in: .capsule)
    }

    private var freshnessText: String {
        guard let last = store.freshness else { return "θ never pulled" }
        let minutes = max(0, Int(Date().timeIntervalSince(last) / 60))
        if minutes < 1 { return "θ just pulled" }
        if minutes < 60 { return "θ pulled \(minutes)m ago" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "θ pulled \(h)h ago" : "θ pulled \(h)h \(m)m ago"
    }

    private var freshnessColor: Color {
        guard let last = store.freshness else { return Color.theme.neg }
        let minutes = Date().timeIntervalSince(last) / 60
        if minutes < 30  { return Color.theme.pos }
        if minutes < 120 { return Color.theme.warn }
        return Color.theme.neg
    }

    /// Hint for the next refresh. During market hours we estimate it
    /// at "next 15-min slot". Outside, we just note the cron is paused.
    private var nextRefreshHint: String? {
        let eastern = TimeZone(identifier: "America/New_York") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: Date())
        guard let wd = comps.weekday, let h = comps.hour, let m = comps.minute else { return nil }
        let isWeekday = wd >= 2 && wd <= 6
        let inMarket  = isWeekday && h >= 9 && h < 15
        if inMarket {
            let mins = m % 15
            return "next pull in \(15 - mins)m"
        }
        return "cron paused · resumes 9:00 EST"
    }

    // ── Period toggle ── (iOS 26 liquid glass via SegmentedToggle)
    private var periodToggle: some View {
        SegmentedToggle(selection: $period, label: { $0.rawValue })
    }

    // ── DAY view ──
    private var dayView: some View {
        VStack(alignment: .leading, spacing: 16) {
            portfolioHero
            if !snap.cliffLegs.isEmpty { cliffWatchSection }
            perTickerSection(period: .day)
            // Stress test parked — coming back in a future pass.
        }
    }

    // ── WEEK view (redesigned) ──
    //
    // Default focus is LAST WEEK with a per-day bar chart so the user
    // can see how θ moved day-by-day. THIS WEEK PROJECTED is a smaller
    // secondary card. Prior weeks below get visual mini bars on each
    // row so weeks are comparable at a glance.
    private var weekView: some View {
        VStack(alignment: .leading, spacing: 16) {
            lastWeekCard
            thisWeekProjectedCard
            priorWeeksCard
            perTickerSection(period: .week)
        }
    }

    /// LAST WEEK card — per-day grouped bar chart (paid coral / sold
    /// neon), plus totals row.
    @ViewBuilder
    private var lastWeekCard: some View {
        if let mon = HedgeHistory.lastWeekMonday() {
            let days = HedgeHistory.dailyBreakdown(
                weekStart: mon,
                snapshots: store.dailyTheta,
                trades: store.allTrades
            )
            let totalPaid = days.reduce(0) { $0 + $1.paid }
            let totalSold = days.reduce(0) { $0 + $1.sold }
            let net = totalSold - totalPaid
            let hasData = totalPaid > 0 || totalSold > 0

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("LAST WEEK")
                        .font(.ui(size: 12, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.theme.fg2)
                    Spacer()
                    Text(weekLabel(monday: mon))
                        .font(.numeric(size: 11, weight: .semibold))
                        .foregroundStyle(Color.theme.fg3)
                }

                if hasData {
                    // Big totals row first — the headline.
                    HStack(alignment: .top, spacing: 4) {
                        weekStat(title: "PAID",   value: "−\(fmtMoney(totalPaid))", tone: Color.theme.neg)
                        weekStat(title: "SOLD",   value: "+\(fmtMoney(totalSold))", tone: Color.theme.neon)
                        weekStat(title: "NET",    value: fmtMoney(net, sign: true), tone: Color.signed(net))
                    }
                    perDayBarChart(days: days, period: .week)
                } else {
                    weekEmpty
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .navCard(
                stroke: hasData
                    ? (net >= 0 ? Color.theme.pos.opacity(0.35) : Color.theme.warn.opacity(0.40))
                    : Color.theme.neon.opacity(0.18)
            )
        }
    }

    @ViewBuilder
    private var weekEmpty: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
            Text("History builds as the nightly snapshot runs.")
                .font(.ui(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color.theme.fg4)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func weekStat(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.ui(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Color.theme.fg3)
            Text(value)
                .font(.numeric(size: 18, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Per-day NET bar chart in the same style as the Trades premium
    /// chart and Performance charts — boxy diverging bars over a
    /// zero-line, sold > paid renders positive (green), paid > sold
    /// renders negative (red). The totals row above the chart already
    /// breaks out PAID vs SOLD, so the chart focuses on net per day.
    @ViewBuilder
    private func perDayBarChart(days: [DailyBreakdown], period: Period) -> some View {
        let bars: [BarPoint] = days.enumerated().map { idx, d in
            BarPoint(
                id: idx,
                x: idx,
                value: d.isPast ? (d.sold - d.paid) : 0,
                label: d.weekdayLetter
            )
        }
        DeltaBarChart(bars: bars, height: 110)
    }


    /// "May 19 – May 23" formatting for week range.
    private func weekLabel(monday: Date) -> String {
        guard let eastern = TimeZone(identifier: "America/New_York") else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = eastern
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = eastern
        let fri = cal.date(byAdding: .day, value: 4, to: monday) ?? monday
        return "\(f.string(from: monday)) – \(f.string(from: fri))"
    }

    /// THIS WEEK secondary card — compact projected progress.
    @ViewBuilder
    private var thisWeekProjectedCard: some View {
        let projected = snap.totalBurn * 5
        let collected = store.shortCallPremiumCollected(since: AppDates.startOfWeek(Date()))
        let target = max(projected, 0.01)
        let progress = min(1.0, collected / target)
        let pctInt = Int((collected / target * 100).rounded())
        let covered = collected >= projected

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("THIS WEEK · PROJECTED")
                    .font(.ui(size: 10, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(Color.theme.fg2)
                Spacer()
                Text("today × 5d")
                    .font(.ui(size: 9, weight: .semibold))
                    .foregroundStyle(Color.theme.fg4)
            }
            HStack(alignment: .lastTextBaseline) {
                Text(fmtMoney(collected))
                    .font(.numeric(size: 18, weight: .bold))
                    .foregroundStyle(covered ? Color.theme.pos : Color.theme.neon)
                Text("/ \(fmtMoney(projected))")
                    .font(.numeric(size: 12, weight: .semibold))
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                Text("\(pctInt)%")
                    .font(.numeric(size: 13, weight: .bold))
                    .foregroundStyle(covered ? Color.theme.pos : Color.theme.neon)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.theme.soft.opacity(0.4))
                    Capsule()
                        .fill(covered ? Color.theme.pos : Color.theme.neon)
                        .frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .navCard(stroke: Color.theme.neon.opacity(0.18))
    }

    // ── Prior weeks ──
    //
    // Each week is its own card with a mini per-day bar chart so weeks
    // are comparable at a glance. Net at right tells you whether the
    // hedge was self-funded that week.
    @ViewBuilder
    private var priorWeeksCard: some View {
        let weeks = priorWeeks
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("PRIOR WEEKS")
                    .font(.ui(size: 12, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(Color.theme.fg2)
                Spacer()
                Text("paid vs collected")
                    .font(.ui(size: 10, weight: .semibold))
                    .foregroundStyle(Color.theme.fg3)
            }
            if weeks.isEmpty || weeks.allSatisfy({ $0.paid == 0 && $0.sold == 0 }) {
                weekEmpty
            } else {
                VStack(spacing: 10) {
                    ForEach(weeks) { w in priorWeekCard(w) }
                }
            }
        }
    }

    /// One week — bigger card with day bars + 3-column totals.
    @ViewBuilder
    private func priorWeekCard(_ w: PriorWeekSummary) -> some View {
        // Build the daily breakdown for THIS specific week.
        let monday = isoDate(w.weekStartISO) ?? Date()
        let days = HedgeHistory.dailyBreakdown(
            weekStart: monday,
            snapshots: store.dailyTheta,
            trades: store.allTrades
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Wk of \(AppDates.shortMonthDay(w.weekStartISO))")
                    .font(.ui(size: 14, weight: .bold))
                    .foregroundStyle(Color.theme.fg1)
                Text(w.covered ? "covered" : "short")
                    .font(.ui(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(w.covered ? Color.theme.pos : Color.theme.warn)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().strokeBorder(
                            (w.covered ? Color.theme.pos : Color.theme.warn).opacity(0.4),
                            lineWidth: 1
                        )
                    )
                Spacer()
                Text(fmtMoney(w.net, sign: true))
                    .font(.numeric(size: 16, weight: .bold))
                    .foregroundStyle(Color.signed(w.net))
            }

            miniPerDayBars(days: days)

            // Single mono line totals — paid + sold + net signal is
            // already carried by the bar colors, no need for legend
            // bullets.
            HStack(spacing: 14) {
                Text("paid −\(fmtMoney(w.paid)) · sold +\(fmtMoney(w.sold))")
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .navCard(
            stroke: w.covered ? Color.theme.pos.opacity(0.30)
                              : Color.theme.warn.opacity(0.35)
        )
    }

    /// Compact NET-per-day bars for the prior-week cards — same
    /// DeltaBarChart style at a smaller height.
    @ViewBuilder
    private func miniPerDayBars(days: [DailyBreakdown]) -> some View {
        let bars: [BarPoint] = days.enumerated().map { idx, d in
            BarPoint(id: idx, x: idx, value: d.sold - d.paid, label: d.weekdayLetter)
        }
        DeltaBarChart(bars: bars, height: 60)
    }

    /// Parse "YYYY-MM-DD" → Date in EST.
    private func isoDate(_ s: String) -> Date? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "America/New_York")
        return df.date(from: s)
    }

    // ── Portfolio θ hero (DAY) — new Navi-light layout ──
    //
    // Top:    "Portfolio θ" heroTitle + subtitle "Daily theta decay
    //         across open positions" + "long puts only" right
    // Stats:  3-col TODAY / YESTERDAY / CHANGE — only TODAY and CHANGE
    //         carry the coral signal; YESTERDAY stays fg1 ink so the
    //         eye lands on what's changing.
    // Gauge:  inset page-2 card with "DECAY EXPOSURE · TODAY" eyebrow
    //         + the full pos→warn→neg meter with CALM/CRITICAL labels.
    // Below:  dashed divider, then a flat "✦ EXPOSURE · N POSITIONS"
    //         insight-style block with CALM / AT CLIFF count columns.
    // Note:   sparkline-builds caveat sits at the bottom in mono fg3.
    private var portfolioHero: some View {
        let calmCount = (snap.zoneCounts[.calm] ?? 0) + (snap.zoneCounts[.watch] ?? 0)
        let cliffCount = (snap.zoneCounts[.cliff] ?? 0) + (snap.zoneCounts[.critical] ?? 0)

        return VStack(alignment: .leading, spacing: 16) {
            // Header — hero + subtitle, "long puts only" inline right.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio θ")
                        .heroTitle()
                    Text("Daily theta decay across open positions")
                        .font(.numeric(size: 13))
                        .foregroundStyle(Color.theme.fg3)
                }
                Spacer()
                Text("long puts only")
                    .font(.numeric(size: 13))
                    .foregroundStyle(Color.theme.fg3)
            }
            Rectangle().fill(Color.theme.borderBright).frame(height: 1)

            heroComparisonRow

            // Decay exposure inset card with eyebrow + gauge.
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Text("DECAY EXPOSURE · TODAY")
                        .font(.ui(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.theme.fg3)
                    Spacer()
                }
                zoneGauge
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.theme.page2)
            )

            DashedHairline()
                .padding(.vertical, -2)

            // Exposure breakdown — sparkle eyebrow + two count columns.
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.theme.neon)
                Text("EXPOSURE · \(snap.legs.count) POSITION\(snap.legs.count == 1 ? "" : "S")")
                    .font(.ui(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.theme.neon)
                Spacer()
            }
            HStack(alignment: .top, spacing: 0) {
                exposureCountCell(label: "CALM",     value: calmCount,  tone: Color.theme.pos)
                exposureCountCell(label: "AT CLIFF", value: cliffCount, tone: Color.theme.warn)
            }

            // Sparkline-builds caveat — bottom mono note.
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                Text("Sparkline builds as the nightly snapshot runs.")
                    .font(.numeric(size: 12))
            }
            .foregroundStyle(Color.theme.fg3)

            if snap.legsMissingGreeks > 0 {
                Text("\(snap.legsMissingGreeks) leg\(snap.legsMissingGreeks == 1 ? "" : "s") missing θ — number is partial.")
                    .font(.ui(size: 11, weight: .semibold))
                    .foregroundStyle(Color.theme.warn)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(
                    LinearGradient(
                        colors: [Color.cardGrad.top, Color.cardGrad.bot],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl)
                        .strokeBorder(Color.theme.borderBright, lineWidth: 1)
                )
                .shadow(color: Color.cardGrad.glow, radius: 12, x: 0, y: 0)
        )
    }

    /// EXPOSURE row cell — caps label + big heavy count below in `tone`.
    @ViewBuilder
    private func exposureCountCell(label: String, value: Int, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.ui(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.theme.fg3)
            Text("\(value)")
                .font(.ui(size: 30, weight: .heavy))
                .tracking(-0.6)
                .foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Three-column TODAY / YESTERDAY / CHANGE row matching the new
    /// design — TODAY and CHANGE in coral, YESTERDAY in fg1 ink so the
    /// reference doesn't compete with the live signal. Change carries a
    /// ▼/▲ triangle + "more decay" / "less decay" caption rather than a
    /// percentage.
    @ViewBuilder
    private var heroComparisonRow: some View {
        let change = dayDelta.change
        let worse = (change ?? 0) > 0    // burn grew = more decay
        let tone: Color = {
            guard let c = change else { return Color.theme.fg4 }
            if abs(c) < 0.01 { return Color.theme.fg3 }
            return worse ? Color.theme.neg : Color.theme.pos
        }()

        HStack(alignment: .top, spacing: 8) {
            // TODAY — heavy coral, "/ day" caption.
            statColumn(label: "TODAY") {
                Text("−\(fmtMoney(snap.totalBurn))")
                    .font(.ui(size: 26, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color.theme.neg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("/ day")
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            }

            // YESTERDAY — same weight, fg1 ink (no signal color, it's
            // the reference number).
            statColumn(label: "YESTERDAY") {
                if let p = dayDelta.priorBurn {
                    Text("−\(fmtMoney(p))")
                        .font(.ui(size: 26, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(Color.theme.fg1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text("—")
                        .font(.ui(size: 26, weight: .heavy))
                        .foregroundStyle(Color.theme.fg4)
                }
                Text("/ day")
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg3)
            }

            // CHANGE — ▼ more decay (worse) / ▲ less decay (better).
            // Value renders as a signed dollar from the holder's P&L
            // perspective: negative when burn increased.
            statColumn(label: "CHANGE") {
                if let c = change, abs(c) >= 0.01 {
                    Text(worse ? "−\(fmtMoney(abs(c)))" : "+\(fmtMoney(abs(c)))")
                        .font(.ui(size: 26, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(tone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 4) {
                        Image(systemName: worse ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                            .font(.system(size: 8))
                        Text(worse ? "more decay" : "less decay")
                    }
                    .font(.numeric(size: 11))
                    .foregroundStyle(Color.theme.fg3)
                } else if change != nil {
                    Text("$0")
                        .font(.ui(size: 26, weight: .heavy))
                        .foregroundStyle(Color.theme.fg3)
                    Text("unchanged")
                        .font(.numeric(size: 11))
                        .foregroundStyle(Color.theme.fg3)
                } else {
                    Text("—")
                        .font(.ui(size: 26, weight: .heavy))
                        .foregroundStyle(Color.theme.fg4)
                    Text("needs prior snap")
                        .font(.numeric(size: 11))
                        .foregroundStyle(Color.theme.fg4)
                }
            }
        }
    }

    /// Reusable 3-col cell: caps label on top, supplied content below.
    @ViewBuilder
    private func statColumn<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.ui(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.theme.fg3)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 14-day theta sparkline — hand-rolled mini bar chart. Last bar
    /// (today) gets a brighter coral so the latest reading stands out.
    /// Renders nothing when there's only one point (no shape yet).
    @ViewBuilder
    private var sparklineStrip: some View {
        let pts = sparkline
        if pts.count >= 2 {
            let maxV = max(pts.map(\.value).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(pts.enumerated()), id: \.element.id) { idx, pt in
                        let isLast = idx == pts.count - 1
                        let h = max(2, CGFloat(pt.value / maxV) * 32)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(isLast ? Color.theme.neg : Color.theme.neg.opacity(0.45))
                            .frame(width: 6, height: h)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 32)

                Text("Last \(pts.count) trading day\(pts.count == 1 ? "" : "s") — today right.")
                    .font(.ui(size: 9, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(Color.theme.fg4)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                Text("Sparkline builds as the nightly snapshot runs.")
                    .font(.ui(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.theme.fg4)
        }
    }

    /// Calm → Critical gauge. The full semantic spectrum is always drawn
    /// (pos → soft sage → warn → neg) and the un-reached portion is
    /// covered by a dusk overlay — so the meter visually communicates
    /// "current exposure level" rather than "fill grows with stress".
    /// Matches HTML .th-meter.
    private var zoneGauge: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.theme.pos,                            location: 0.0),
                                    .init(color: Color.theme.pos.opacity(0.65),              location: 0.30),
                                    .init(color: Color.theme.warn,                           location: 0.60),
                                    .init(color: Color.theme.neg.opacity(0.75),              location: 0.80),
                                    .init(color: Color.theme.neg,                            location: 1.0)
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                    // Dusk overlay covers the un-reached portion.
                    GeometryReader { _ in
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(Color.theme.dusk)
                                .frame(width: max(0, geo.size.width * (1 - snap.worstZone.gaugeFraction)))
                        }
                    }
                }
                .clipShape(Capsule())
                .animation(Motion.easeOut, value: snap.worstZone)
            }
            .frame(height: 10)

            HStack {
                Text("CALM")
                    .font(.ui(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                Text("CRITICAL")
                    .font(.ui(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.theme.fg3)
            }
        }
    }

    private func zoneChip(zone: HedgeZone, count: Int) -> some View {
        // Matches HTML .th-chip — filled with the matching tint, mono
        // caps, slight title-case label.
        let bg: Color = {
            switch zone {
            case .calm:     return Color.theme.tintPos
            case .watch:    return Color.theme.tintMuted
            case .cliff:    return Color.theme.tintWarn
            case .critical: return Color.theme.tintNeg
            }
        }()
        return Text("\(count) \(zone.label.lowercased())")
            .font(.ui(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(zone.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(bg)
                    .overlay(Capsule().strokeBorder(zone.color.opacity(0.5), lineWidth: 1))
            )
    }

    // ── Cliff watch — horizontal row of triage cards ──
    //
    // New layout: section header on top, then a horizontal-scrolling
    // row of compact cards (one per cliff/critical leg). Each card has
    // a colored top stripe whose tone reflects how imminent the next
    // zone transition is — coral if the leg drops into critical within
    // 5 days (or is already there), amber otherwise.
    private var cliffWatchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.theme.warn)
                    Text("Theta cliff watch")
                        .font(.ui(size: 18, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.theme.fg1)
                }
                Spacer()
                Text("\(snap.cliffLegs.count) position\(snap.cliffLegs.count == 1 ? "" : "s")")
                    .font(.numeric(size: 13))
                    .foregroundStyle(Color.theme.fg3)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(snap.cliffLegs) { leg in
                        cliffCard(leg)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// Compact triage card — fixed width so the row scrolls cleanly at
    /// any iPhone size. Layout: colored top stripe (imminence cue) →
    /// CLIFF badge → ticker → strike·ct mono → big per-day burn → DTE
    /// → escalation arrow.
    @ViewBuilder
    private func cliffCard(_ leg: HedgeLegLive) -> some View {
        // Imminence tone: coral if escalating into critical within 5
        // days (or already critical), else amber for plain cliff legs.
        let stripeTone: Color = {
            if leg.zone == .critical { return Color.theme.neg }
            if let days = leg.daysToNextZone,
               leg.nextZone == .critical,
               days <= 5 {
                return Color.theme.neg
            }
            return Color.theme.warn
        }()

        Button {
            sheetTicker = leg.ticker
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Top stripe — 5pt tall colored bar, full card width.
                Rectangle()
                    .fill(stripeTone)
                    .frame(height: 5)

                VStack(alignment: .leading, spacing: 12) {
                    // CLIFF / CRITICAL badge.
                    Text(leg.zone.label.capitalized)
                        .font(.ui(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(leg.zone.color)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.theme.tintMuted)
                                .overlay(Capsule().strokeBorder(leg.zone.color.opacity(0.45), lineWidth: 1))
                        )

                    // Ticker.
                    Text(leg.ticker)
                        .font(.ui(size: 22, weight: .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(Color.theme.fg1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    // Strike · contract count.
                    Text("$\(fmtStrike(leg.strike))p · \(Int(leg.contractsRemaining)) ct")
                        .font(.numeric(size: 12))
                        .foregroundStyle(Color.theme.fg3)

                    // Per-day burn hero — big coral, "/day" caption inline.
                    if let burn = leg.dailyBurn {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("−\(fmtMoney(burn))")
                                .font(.ui(size: 24, weight: .heavy))
                                .tracking(-0.5)
                                .foregroundStyle(Color.theme.neg)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("/day")
                                .font(.numeric(size: 11))
                                .foregroundStyle(Color.theme.fg3)
                        }
                    } else {
                        Text("θ pending")
                            .font(.ui(size: 12, weight: .semibold))
                            .foregroundStyle(Color.theme.fg4)
                    }

                    // DTE.
                    Text("\(leg.dte)d left")
                        .font(.numeric(size: 12))
                        .foregroundStyle(Color.theme.fg3)

                    // Escalation — "→ Critical in 4d" in the next-zone color.
                    if let days = leg.daysToNextZone, let nz = leg.nextZone {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(nz.label.capitalized) in \(days)d")
                                .font(.numeric(size: 12, weight: .medium))
                        }
                        .foregroundStyle(nz.color)
                        .lineLimit(1)
                    }
                }
                .padding(16)
            }
            .frame(width: 200, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg)
                            .strokeBorder(Color.theme.borderBright, lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .shadow(color: Color.cardGrad.glow, radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.pressable)
    }

    // ── Per-ticker section with zone filter chips ──
    private func perTickerSection(period: Period) -> some View {
        let groups = filteredTickerGroups
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("PER TICKER")
                    .font(.ui(size: 12, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(Color.theme.fg2)
                Spacer()
                Text("\(groups.count) of \(snap.byTicker.count)")
                    .font(.numeric(size: 11, weight: .semibold))
                    .foregroundStyle(Color.theme.fg3)
            }

            // Filter chips — counts reflect legs in each zone band.
            zoneFilterChips

            if groups.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("No legs match this filter.")
                        .font(.ui(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.theme.fg4)
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 12) {
                    ForEach(groups, id: \.ticker) { group in
                        perTickerCard(ticker: group.ticker, legs: group.legs, period: period)
                    }
                }
            }
        }
    }

    /// Filter pills above the per-ticker list. Each chip shows the
    /// number of legs that would survive that filter.
    private var zoneFilterChips: some View {
        // Counts per filter
        let total = snap.legs.count
        let watchPlus    = snap.legs.filter { $0.zone >= .watch }.count
        let cliffPlus    = snap.legs.filter { $0.zone >= .cliff }.count
        let criticalOnly = snap.legs.filter { $0.zone == .critical }.count

        let pills: [(ZoneFilter, Int)] = [
            (.all,          total),
            (.watchPlus,    watchPlus),
            (.cliffPlus,    cliffPlus),
            (.criticalOnly, criticalOnly),
        ]

        // GlassEffectContainer lets multiple `.glassEffect()` pills
        // share one surface — iOS 26 morphs them together as the user
        // pans / taps, instead of each pill rendering a separate
        // material island.
        return ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(pills, id: \.0) { p in
                        filterChip(filter: p.0, count: p.1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func filterChip(filter: ZoneFilter, count: Int) -> some View {
        // Matches HTML .td-tab: pill with title (Sentence/Title case)
        // + inset count badge. Active state recesses into page-2; cliff
        // and critical filters carry their semantic tint on the border.
        let active = zoneFilter == filter
        let tint = filter.tint
        let titleCase: String = {
            switch filter {
            case .all:          return "All"
            case .watchPlus:    return "Watch+"
            case .cliffPlus:    return "Cliff+"
            case .criticalOnly: return "Critical"
            }
        }()
        Button {
            withAnimation(Motion.standard) { zoneFilter = filter }
        } label: {
            HStack(spacing: 8) {
                Text(titleCase)
                    .font(.ui(size: 12, weight: .semibold))
                    .tracking(0.4)
                Text("\(count)")
                    .font(.numeric(size: 11, weight: .bold))
                    .foregroundStyle(active ? tint : Color.theme.fg3)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            active ? Color.theme.surface
                                   : Color.theme.tintMuted
                        )
                    )
            }
            .foregroundStyle(active ? Color.theme.fg1 : tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(
                .regular.tint(active ? Color.theme.page2.opacity(0.7) : Color.theme.surface.opacity(0.6)),
                in: .capsule
            )
            .overlay(
                Capsule().strokeBorder(
                    active ? Color.theme.borderBright : tint.opacity(0.5),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(count == 0 && filter != .all)
        .opacity(count == 0 && filter != .all ? 0.4 : 1)
    }

    @ViewBuilder
    private func perTickerCard(ticker: String, legs: [HedgeLegLive], period: Period) -> some View {
        let totalToday = legs.compactMap(\.dailyBurn).reduce(0, +)
        // worst zone among legs in this card → drives the border tone
        let worst = legs.map(\.zone).max() ?? .calm
        // WEEK projection: today × 5 trading days. Honest approximation,
        // not curve-integrated (would need theta-acceleration math).
        let projected = totalToday * 5

        Button {
            sheetTicker = ticker
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Top row — ticker name + total burn
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ticker)
                            .font(.ui(size: 22, weight: .bold))
                            .foregroundStyle(Color.theme.fg1)
                        if let name = TickerNames.name(for: ticker) {
                            Text(name)
                                .font(.ui(size: 11, weight: .medium))
                                .foregroundStyle(Color.theme.fg3)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(period == .day ? "−\(fmtMoney(totalToday))"
                                            : "−\(fmtMoney(projected))")
                            .font(.numeric(size: 20, weight: .bold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.theme.neg)
                        Text(period == .day ? "per day" : "per wk (projected)")
                            .font(.ui(size: 9, weight: .semibold))
                            .foregroundStyle(Color.theme.fg3)
                    }
                }

                // Per-leg breakdown — each leg gets its own inset row
                VStack(spacing: 8) {
                    ForEach(legs) { leg in perLegRow(leg) }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .navCard(
                stroke: worst >= .cliff
                    ? worst.color.opacity(0.45)
                    : Color.theme.neon.opacity(0.18)
            )
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder
    private func perLegRow(_ leg: HedgeLegLive) -> some View {
        // Matches HTML .td-leg: page-2 inset, strike heavy left, badge
        // right, zone-tinted progress bar in the middle, mono footer
        // with θ · −$x/d · DTE · escalation arrow.
        let badgeBg: Color = {
            switch leg.zone {
            case .calm:     return Color.theme.tintPos
            case .watch:    return Color.theme.tintMuted
            case .cliff:    return Color.theme.tintWarn
            case .critical: return Color.theme.tintNeg
            }
        }()

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("$\(fmtStrike(leg.strike))p")
                    .font(.ui(size: 17, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(Color.theme.fg1)
                Text("\(AppDates.shortMonthDay(leg.expiry)) · \(Int(leg.contractsRemaining)) ct")
                    .font(.numeric(size: 12))
                    .foregroundStyle(Color.theme.fg3)
                Spacer()
                Text(leg.zone.label.capitalized)
                    .font(.ui(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(leg.zone.color)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(badgeBg)
                            .overlay(Capsule().strokeBorder(leg.zone.color.opacity(0.55), lineWidth: 1))
                    )
            }

            // Zone-tinted decay bar (HTML .td-bar / .fill).
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.theme.dusk)
                    Capsule()
                        .fill(leg.zone.color)
                        .frame(width: max(6, geo.size.width * leg.zone.gaugeFraction))
                }
            }
            .frame(height: 8)

            HStack(spacing: 8) {
                if let t = leg.thetaPerShare, let b = leg.dailyBurn {
                    Text("θ \(String(format: "%.2f", abs(t)))")
                        .font(.numeric(size: 12, weight: .medium))
                        .foregroundStyle(Color.theme.fg2)
                    Text("·").foregroundStyle(Color.theme.fg4)
                    Text("−\(fmtMoney(b))/d")
                        .font(.numeric(size: 12, weight: .semibold))
                        .foregroundStyle(Color.theme.neg)
                    Text("·").foregroundStyle(Color.theme.fg4)
                    Text("\(leg.dte)d left")
                        .font(.numeric(size: 12))
                        .foregroundStyle(Color.theme.fg3)
                } else {
                    Text("θ pending · \(leg.dte)d left")
                        .font(.ui(size: 12, weight: .medium))
                        .foregroundStyle(Color.theme.fg4)
                }
                Spacer()
                if let days = leg.daysToNextZone, let nz = leg.nextZone {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(nz.label.capitalized) in \(days)d")
                            .font(.numeric(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(nz.color)
                }
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.theme.page2)
        )
    }

}

/// Identifiable wrapper for using a String with `.sheet(item:)`.
private struct IdentifiedString: Identifiable {
    let value: String
    var id: String { value }
}
