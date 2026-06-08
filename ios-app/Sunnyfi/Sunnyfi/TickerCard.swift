//
//  TickerCard.swift
//  Sunnyfi
//
//  Unified per-ticker positions card — full rebuild against
//  Positions Handoff 2. Every layout decision tracks the CSS rules
//  in §0 "THE ALIGNMENT RULES":
//
//    • Single 21px inset (1px border + 20px content padding) for
//      every zone — ticker, greeks-first-cell, section labels, stat
//      grid, leg titles, return rows. Nothing drifts.
//    • Header is BASELINE-aligned — `firstTextBaseline` so the
//      24pt ticker and 21pt mono hero sit on one line.
//    • Horizontal rules between return rows are FULL-BLEED — the
//      content is 20pt-inset but the rule extends edge-to-edge.
//      Implemented as a sibling `Rectangle` in the card's outer
//      VStack rather than an overlay on the inset content.
//    • Same-kind rows (Today / Total return) carry identical
//      padding so they read as a pair.
//    • Every greeks-band cell has label + value + sub (none lopsided).
//    • Swipe-to-close action sits BEHIND an opaque (`surface`) row
//      that fully covers the wrapper — no peeking sliver.
//
//  Color rule (Handoff §1, applies invariantly):
//    • Dollar values are always `--fg1`.
//    • Percentages are always sign-colored AND use ↑/↓ arrows
//      (via the global `fmtPct` change).
//

import SwiftUI

// MARK: - Card-level inset constants

private enum CardInset {
    static let h: CGFloat = 20      // content x-padding inside the card
    static let outer: CGFloat = 1   // border line width
    /// 21px = 20 content padding + 1 border. Used by anything that
    /// needs to align ABOVE the leg content (e.g. greeks panel margin
    /// from the card edge).
    static let total: CGFloat = h + outer
}

// MARK: - PRow (the canonical label/dollar/pct row)

/// One label + value row. Dollar amount renders BLACK (`fg1`);
/// percentage is sign-colored using the global ↑/↓ format. Used by
/// Today's return, Total return, If exercised, and the Open-call-
/// credit card.
struct PRow: View {
    let label: String
    let amount: Double
    let amountSign: Bool      // include +/− on the dollar?
    let pct: Double?
    let pctAccent: PctAccent  // override color (e.g. neon for If exercised)
    let spark: Bool           // show the ✦ neon glyph before the label?

    init(label: String,
         amount: Double,
         amountSign: Bool = true,
         pct: Double? = nil,
         pctAccent: PctAccent = .auto,
         spark: Bool = false) {
        self.label = label
        self.amount = amount
        self.amountSign = amountSign
        self.pct = pct
        self.pctAccent = pctAccent
        self.spark = spark
    }

    enum PctAccent { case auto, neon, dollarSign }

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 6) {
                if spark {
                    Text("✦")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.theme.neon)
                }
                Text(label)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.theme.labelMuted)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(fmtMoney(amount, sign: amountSign))
                    .font(.system(size: 16, weight: .medium))
                    .monospacedDigit()
                    .tracking(-0.16)
                    .foregroundStyle(Color.theme.fg1)
                    .lineLimit(1)
                if let p = pct {
                    Text(fmtPctParens(p))
                        .font(.system(size: 12.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(pctColor(for: p))
                        .lineLimit(1)
                }
            }
        }
    }

    private func pctColor(for v: Double) -> Color {
        switch pctAccent {
        case .neon: return Color.theme.neon
        case .dollarSign:
            return amount > 0 ? Color.theme.pos : amount < 0 ? Color.theme.neg : Color.theme.fg3
        case .auto:
            return v > 0 ? Color.theme.pos : v < 0 ? Color.theme.neg : Color.theme.fg3
        }
    }
}

/// `(↑0.50%)` / `(↓1.75%)` — wrap fmtPct in parens for the return row.
private func fmtPctParens(_ v: Double) -> String { "(\(fmtPct(v)))" }

// MARK: - Open call credit card (All view only)

/// Same `tcard` chrome as the ticker card, but with a single "leg"
/// containing two rows: Collected (+$11,990) and Value now ($11,660,
/// ↑2.75%). Per Handoff §4.
struct OpenCallCard: View {
    let collected: Double
    let valueNow: Double
    /// Extrinsic / time-value portion of `valueNow`. The "money still
    /// at risk to decay" — drops to zero at expiry, leaving only
    /// intrinsic behind.
    let timeValue: Double

    private var gain: Double { collected - valueNow }
    private var gainPct: Double { collected > 0 ? (gain / collected) * 100 : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title sits at 20px inset like every other "leg title".
            Text("Open call credit")
                .font(.system(size: 19, weight: .bold))
                .monospacedDigit()
                .tracking(-0.48)
                .foregroundStyle(Color.theme.fg1)
                .padding(.horizontal, CardInset.h)
                .padding(.top, 14)
                .padding(.bottom, 11)

            // First row has no top hairline per the prototype's
            // `.prow:first-child { border-top: none }` cascade.
            PRow(label: "Collected", amount: collected, amountSign: true, pct: nil)
                .padding(.horizontal, CardInset.h)
                .padding(.vertical, 13)
            FullBleedHair()
            // `.auto` colors by the pct value — gainPct > 0 means the
            // short calls got cheaper to close, the right (green)
            // direction. `dollarSign` would have miscolored because
            // valueNow is always positive.
            PRow(label: "Value now", amount: valueNow, amountSign: false, pct: gainPct)
                .padding(.horizontal, CardInset.h)
                .padding(.vertical, 13)
            FullBleedHair()
            // % = time value / value now × 100. Reads as "X% of the
            // position's current cost-to-close is still extrinsic
            // (decay-vulnerable)". 100% means fully OTM (intrinsic
            // = 0); low % means deep ITM, time decay largely spent.
            PRow(label: "Time value",
                 amount: timeValue,
                 amountSign: false,
                 pct: valueNow > 0 ? (timeValue / valueNow) * 100 : nil)
                .padding(.horizontal, CardInset.h)
                .padding(.vertical, 13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardChrome())
    }
}

// MARK: - Open puts bought card (carousel pair to OpenCallCard)

/// Mirror of `OpenCallCard` but for long puts (the hedge book).
/// Same structure → same three rows, with semantics inverted:
///   • Paid (vs Collected) — what you spent on hedges
///   • Value now — current mark-to-market value
///   • Time value — extrinsic at risk to decay (the "burn rate")
struct OpenPutsBoughtCard: View {
    let paid: Double
    let valueNow: Double
    let timeValue: Double

    /// Gain = current value − cost. Positive when puts have
    /// appreciated (markets fell or vol expanded — your hedges
    /// are working). Negative on decay-only periods.
    private var gain: Double { valueNow - paid }
    private var gainPct: Double { paid > 0 ? (gain / paid) * 100 : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Open puts bought")
                .font(.system(size: 19, weight: .bold))
                .monospacedDigit()
                .tracking(-0.48)
                .foregroundStyle(Color.theme.fg1)
                .padding(.horizontal, CardInset.h)
                .padding(.top, 14)
                .padding(.bottom, 11)

            // First row, no top hair (matches OpenCallCard).
            PRow(label: "Paid", amount: paid, amountSign: false, pct: nil)
                .padding(.horizontal, CardInset.h)
                .padding(.vertical, 13)
            FullBleedHair()
            // Value now — gainPct colored by direction (green when
            // puts appreciate, red when they decay).
            PRow(label: "Value now",
                 amount: valueNow,
                 amountSign: false,
                 pct: gainPct)
                .padding(.horizontal, CardInset.h)
                .padding(.vertical, 13)
            FullBleedHair()
            // Time value — same math as the call card: time value
            // as a percentage of current value. For a BUYER, high
            // % means most of the position is still at risk to
            // decay (mostly OTM); low % means mostly intrinsic
            // (deep ITM, hedge already activated).
            PRow(label: "Time value",
                 amount: timeValue,
                 amountSign: false,
                 pct: valueNow > 0 ? (timeValue / valueNow) * 100 : nil)
                .padding(.horizontal, CardInset.h)
                .padding(.vertical, 13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardChrome())
    }
}

// MARK: - The unified ticker card

struct TickerCard: View {
    let summary: TickerSummary
    let store: PortfolioStore
    /// Caller-owned swipe-close router. Receives the trade to close
    /// (nil = shares leg). The closure decides which sheet to open.
    let onCloseLeg: (OptionTradeRow) -> Void
    let onCloseStock: (String) -> Void
    /// Caller-owned swipe-EDIT router — symmetric to close. Used to
    /// fix a wrong strike / expiry / fill-price entry on a leg the
    /// user logged incorrectly.
    let onEditLeg: (OptionTradeRow) -> Void
    let onEditStock: (String) -> Void
    /// Caller-owned tap on the "Likely assignment · log it →" CTA.
    /// Fires only when a short call is ITM and DTE ≤ 1.
    let onAssign: (OptionTradeRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            greeksPanel
                .padding(.horizontal, CardInset.h)
                .padding(.top, 4)                  // .tcard-greeks margin-top
                .padding(.bottom, 14)              // .tcard-greeks margin-bottom
            legSections
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardChrome())
    }

    // MARK: Header — baseline-aligned ticker + price / hero P&L

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 11) {
                Text(summary.ticker)
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.84)           // -.035em × 24
                    .foregroundStyle(Color.theme.fg1)
                    .lineLimit(1)
                priceLine
            }
            Spacer(minLength: 0)
            // .tcard-net — mono 21pt 600 fg1
            Text(fmtMoney(summary.netPnL, sign: true))
                .font(.system(size: 21, weight: .semibold))
                .monospacedDigit()
                .tracking(-0.525)              // -.025em × 21
                .foregroundStyle(Color.theme.fg1)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, CardInset.h)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    /// `$642.30 ↑0.42%` — mono spot in fg2, arrow-pct sign-colored.
    private var priceLine: some View {
        HStack(spacing: 7) {
            Text(fmtMoney(summary.spot, decimals: 2))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Color.theme.fg2)
            Text(fmtPct(summary.dayPct))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(pctColor(summary.dayPct))
        }
    }

    // MARK: Greeks panel — inset recessed 3-cell strip

    /// `.tcard-greeks` — bg `--page-2`, 1px `--bright` border,
    /// `--radius-lg`. **Not** edge-to-edge — sits inset by the same
    /// 20px content padding. Three EVEN cells, each label+value+sub
    /// (no lopsided cell per §0).
    private var greeksPanel: some View {
        HStack(spacing: 0) {
            greekCell(
                label: "Delta",
                value: fmtGreek(summary.netDelta),
                sub: deltaSub
            )
            greekDivider
            greekCell(
                label: "Calls sold",
                value: "\(summary.callCt)",
                sub: callsSub,
                subAccent: callsAccent
            )
            greekDivider
            greekCell(
                label: "Premium",
                value: fmtMoney(summary.callCredit, sign: false),
                sub: "collected"
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.theme.page2)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.theme.borderBright, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func greekCell(label: String, value: String,
                           sub: String, subAccent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.theme.fg3)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .tracking(-0.30)
                .foregroundStyle(Color.theme.fg1)
                .padding(.top, 6)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            // The .sub line accepts an optional accent fragment for
            // the colored "N%" coverage indicator.
            if let accent = subAccent, summary.shares > 0 && summary.callCt > 0 {
                HStack(spacing: 3) {
                    Text("\(summary.coveredPct)%")
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                    Text("covered")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.theme.fg4)
                }
                .padding(.top, 3)
            } else {
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.theme.fg4)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var greekDivider: some View {
        Rectangle().fill(Color.theme.borderBright)
            .frame(width: 1)
            .frame(maxHeight: 100)
    }

    private var deltaSub: String {
        let d = summary.netDelta
        if d > 0 { return "net long" }
        if d < 0 { return "net short" }
        return "neutral"
    }

    private var callsSub: String {
        if summary.callCt == 0 {
            return summary.shares > 0 ? "uncovered" : "no calls"
        }
        return ""    // when callCt>0 the subAccent branch renders "N% covered"
    }
    private var callsAccent: Color? {
        summary.callCt > 0 ? Color.theme.pos : nil
    }

    // MARK: Sections — Shares first, then Options

    @ViewBuilder
    private var legSections: some View {
        if summary.shareLeg != nil {
            SectionLabel(text: "Shares")
            StockLegView(c: summary,
                         leg: summary.shareLeg!,
                         onSwipeClose: { onCloseStock(summary.ticker) },
                         onSwipeEdit:  { onEditStock(summary.ticker) })
            // Full-bleed hair between Shares and Options per §0.
            if !summary.openLegs.isEmpty {
                FullBleedHair()
            }
        }
        if !summary.openLegs.isEmpty {
            SectionLabel(text: "Options")
            ForEach(Array(summary.openLegs.enumerated()), id: \.element.id) { idx, t in
                if idx > 0 { FullBleedHair() }
                OptionLegView(
                    c: summary,
                    trade: t,
                    store: store,
                    positionNumber: summary.openLegs.count > 1 ? idx + 1 : nil,
                    onSwipeClose: { onCloseLeg(t) },
                    onSwipeEdit:  { onEditLeg(t) },
                    onAssign: { onAssign(t) }
                )
            }
        }
    }
}

// MARK: - Section label

private struct SectionLabel: View {
    let text: String
    var body: some View {
        // `.tsection-lbl` — sans 9pt 600 / 2.2px CAPS / fg3, padding
        // 13/20/2 (matching the 20-inset). 1px underline UNDER JUST
        // THE WORD (not full-bleed) per Handoff §5c.
        HStack {
            Text(text.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(Color.theme.fg3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.theme.fg3)
                        .frame(height: 1)
                        .offset(y: 3)
                }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CardInset.h)
        .padding(.top, 13)
        .padding(.bottom, 6)
    }
}

// MARK: - Stock leg view

struct StockLegView: View {
    let c: TickerSummary
    let leg: Leg
    let onSwipeClose: () -> Void
    let onSwipeEdit: () -> Void

    var body: some View {
        LegSwipeWrap(onEdit: onSwipeEdit, onClose: onSwipeClose) {
            content
        }
    }

    private var content: some View {
        let mv = leg.qty * leg.last
        let basis = leg.qty * leg.avg
        let today = leg.qty * c.spot * (c.dayPct / 100.0)
        let todayPct = basis > 0 ? (today / basis) * 100 : 0
        let total = leg.unreal
        let totalPct = basis > 0 ? (total / basis) * 100 : 0

        return VStack(alignment: .leading, spacing: 0) {
            statGrid([
                ("Shares",       Int(leg.qty).formatted(.number)),
                ("Market value", fmtMoney(mv)),
                ("Avg cost",     fmtMoney(leg.avg, decimals: 2)),
                ("Current",      fmtMoney(leg.last, decimals: 2)),
            ])
            .padding(.horizontal, CardInset.h)
            .padding(.top, 14)
            .padding(.bottom, 8)

            FullBleedHair()
            PRow(label: "Today's return", amount: today, pct: todayPct)
                .padding(.horizontal, CardInset.h)
                .padding(.vertical, 13)
            FullBleedHair()
            PRow(label: "Total return", amount: total, pct: totalPct)
                .padding(.horizontal, CardInset.h)
                .padding(.vertical, 13)
        }
        // Row must be opaque + cover the full wrapper height so the
        // swipe action stays hidden until revealed (§0 invariant).
        .background(Color.theme.surface)
    }
}

// MARK: - Option leg view

struct OptionLegView: View {
    let c: TickerSummary
    let trade: OptionTradeRow
    let store: PortfolioStore
    let positionNumber: Int?
    let onSwipeClose: () -> Void
    let onSwipeEdit: () -> Void
    let onAssign: () -> Void

    var body: some View {
        LegSwipeWrap(onEdit: onSwipeEdit, onClose: onSwipeClose) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let remaining = store.remainingContracts(for: trade)
        let greeks = store.allGreeks.first(where: { $0.option_trade_id == trade.id })
        let mark = greeks?.last_mark ?? trade.premium
        let isShort = trade.direction == "short"
        let dirMul: Double = isShort ? 1 : -1
        let basis = remaining * trade.premium * 100
        let mv = remaining * mark * 100
        let total = (trade.premium - mark) * dirMul * remaining * 100
        let totalPct = basis > 0 ? (total / basis) * 100 : 0

        let dayFrac = c.dayPct / 100.0
        let deltaPnL = (greeks?.delta ?? 0) * (isShort ? -1 : 1) * remaining * 100 * c.spot * dayFrac
        let thetaPnL = (greeks?.theta ?? 0) * (isShort ? -1 : 1) * remaining * 100
        let today = deltaPnL + thetaPnL
        let todayPct = basis > 0 ? (today / basis) * 100 : 0

        let isCall = trade.option_type == "call"
        let itm = isCall ? c.spot > trade.strike : c.spot < trade.strike
        let dte = AppDates.daysUntil(trade.expiry) ?? 999
        let stockAvg = c.shareLeg?.avg ?? 0
        // Show If-exercised ONLY on covered short calls that are
        // currently ITM. The earlier inclusion of long puts (and
        // OTM short calls) was incorrect — long puts here are
        // protective hedges, not positions the user plans to
        // exercise; their P&L lives in the standard Total return
        // row already.
        let canExercise = c.shareLeg != nil && isShort && isCall && itm
        // Short-call assignment profit:
        //   (strike − FIFO stock avg) × ct × 100 + premium collected
        let shareGain = canExercise
            ? (trade.strike - stockAvg) * remaining * 100
            : 0
        let exProfit = canExercise ? shareGain + basis : 0
        let exBasis = canExercise ? remaining * 100 * stockAvg : 0
        let exPct = exBasis > 0 ? (exProfit / exBasis) * 100 : 0

        // CTA only after expiration — DTE 0 is the day the call
        // expires (typically end-of-day assignment notifications),
        // DTE < 0 is past expiry and not yet auto-resolved. The
        // prototype's "DTE ≤ 1" was misleading: on DTE 1 the call
        // is still trading and could close OTM, so flagging
        // assignment is premature.
        let isAssignable = isShort && isCall && itm && dte <= 0

        VStack(alignment: .leading, spacing: 0) {
            if let n = positionNumber {
                HStack(spacing: 6) {
                    Text("Option position \(n)")
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .tracking(0.8)
                        .foregroundStyle(Color.theme.fg4)
                        .textCase(.uppercase)
                    if Self.isFreshlySynced(trade) {
                        Text("NEW")
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.red)
                        Text("(Just updated)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.theme.fg3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, CardInset.h)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }

            // .tleg-top — baseline-aligned title + expiry beside.
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("$\(fmtStrike(trade.strike)) \(isCall ? "Call" : "Put") \(isShort ? "Sold" : "Bought")")
                    .font(.system(size: 19, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.475)         // -.025em × 19
                    .foregroundStyle(Color.theme.fg1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                expiryLabel(dte: dte)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CardInset.h)
            .padding(.top, positionNumber == nil ? 14 : 0)
            .padding(.bottom, 13)

            statGrid([
                ("Contracts",    "\(Int(remaining))"),
                ("Market value", fmtMoney(mv)),
                ("Strike",       "$\(fmtStrike(trade.strike))"),
                ("Fill price",   "$\(String(format: "%.2f", trade.premium))"),
            ])
            .padding(.horizontal, CardInset.h)
            .padding(.bottom, 6)

            FullBleedHair()
            PRow(label: "Today's return", amount: today, pct: todayPct)
                .padding(.horizontal, CardInset.h)
                .padding(.vertical, 13)
            FullBleedHair()
            PRow(label: "Total return", amount: total, pct: totalPct)
                .padding(.horizontal, CardInset.h)
                .padding(.vertical, 13)
            if canExercise {
                FullBleedHair(neonTint: true)
                PRow(label: "If exercised", amount: exProfit, pct: exPct,
                     pctAccent: .neon, spark: true)
                    .padding(.horizontal, CardInset.h)
                    .padding(.vertical, 13)
            }
            if isAssignable {
                assignmentCTA
                    .padding(.horizontal, CardInset.h)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
        .background(Color.theme.surface)
        // (Removed the prior 3px neon left stripe — this design
        // doesn't use the ITM accent bar.)
    }

    /// True if this trade was synced from IBKR within the last 15 min.
    /// Drives the "NEW (Just updated)" badge next to the position header.
    /// Reads from last_synced_at (set on every sync touch — insert or
    /// amendment), so a freshly amended commission also re-flags as new.
    static func isFreshlySynced(_ trade: OptionTradeRow) -> Bool {
        guard trade.source == "ibkr_flex",
              let syncedStr = trade.last_synced_at,
              let synced = parseISO(syncedStr) else {
            return false
        }
        return Date().timeIntervalSince(synced) < 15 * 60
    }

    private static func parseISO(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFrac.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// Expiry chip — "Jun 6" normal, "Expires today" / "Expires
    /// tomorrow" in red when DTE ≤ 1 (§6).
    @ViewBuilder
    private func expiryLabel(dte: Int) -> some View {
        if dte == 0 {
            Text("Expires today")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.theme.neg)
        } else if dte == 1 {
            Text("Expires tomorrow")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.theme.neg)
        } else {
            Text(AppDates.shortMonthDay(trade.expiry))
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(Color.theme.fg3)
        }
    }

    private var assignmentCTA: some View {
        Button(action: onAssign) {
            HStack(spacing: 6) {
                Text("Likely assignment · log it")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Color.theme.neg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.theme.tintNeg)
            )
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Shared full-bleed hairline + stat grid + chrome

/// Full-width, edge-to-edge horizontal rule. Rendered as a sibling
/// inside the card's outer VStack so it spans the card width, not the
/// 20-inset content. Per §0 invariant.
struct FullBleedHair: View {
    var neonTint: Bool = false
    var body: some View {
        Rectangle()
            .fill(neonTint
                  ? Color.theme.neon.opacity(0.22)
                  : Color.theme.borderBright.opacity(0.5))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// 2×2 stat grid — labels muted (`labelMuted`), values black mono
/// 18pt 500. Per `.tleg-grid` + `.tleg-stat`.
@ViewBuilder
private func statGrid(_ cells: [(String, String)]) -> some View {
    let pairs = cells.chunked(into: 2)
    VStack(alignment: .leading, spacing: 18) {
        ForEach(pairs.indices, id: \.self) { i in
            HStack(spacing: 16) {
                ForEach(pairs[i].indices, id: \.self) { j in
                    let (k, v) = pairs[i][j]
                    VStack(alignment: .leading, spacing: 5) {
                        Text(k)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.theme.labelMuted)
                        Text(v)
                            .font(.system(size: 18, weight: .medium))
                            .monospacedDigit()
                            .tracking(-0.36)
                            .foregroundStyle(Color.theme.fg1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Shared card chrome — surface fill, 1px bright border, radius-lg,
/// shadow-card.
private struct CardChrome: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.lg)
            .fill(Color.theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.theme.borderBright, lineWidth: 1)
            )
            .shadow(color: Color.cardGrad.glow, radius: 6, x: 0, y: 2)
    }
}

private func pctColor(_ v: Double) -> Color {
    v > 0 ? Color.theme.pos : v < 0 ? Color.theme.neg : Color.theme.fg3
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

// MARK: - LegSwipeWrap — swipe-left to reveal Close

/// Wraps a leg row in a swipe-to-close container. Drag the row left
/// to reveal a 79pt-wide red Close action; release past half-way and
/// it snaps open. Tapping Close fires `onClose`. The row content is
/// `surface`-opaque and fully covers the wrapper so the action stays
/// hidden until revealed (§0 invariant).
/// Swipe-left → Close. Coexists with the parent ScrollView by being
/// EXTREMELY conservative about engaging:
///   • Minimum 30pt drag distance before considering activation.
///   • Only engages on clearly LEFTWARD drag (negative dx).
///   • Requires `|dx| > 2.5 × |dy|` — a near-flat horizontal motion.
///   • Stateless per-drag — no `lock` enum carrying across drags
///     (the prior implementation could get stuck in `.vertical`).
///   • Uses `simultaneousGesture` so the ScrollView's vertical
///     gesture still gets the touch when this one declines to
///     mutate offset.
///
/// In practice: a normal vertical scroll drag has dx ≈ 0 and dy
/// large — falls through to scroll. A clear left swipe past 30pt
/// engages the close action.
struct LegSwipeWrap<Content: View>: View {
    /// When non-nil, an additional "Edit" action appears to the
    /// LEFT of the Close action in the swipe reveal. Used by option
    /// legs (where the user might need to fix strike/expiry/etc on
    /// a trade they logged with the wrong details). Shares legs
    /// don't pass this — they only need Close.
    let onEdit: (() -> Void)?
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var open = false
    private let actionWidth: CGFloat = 79
    private var revealWidth: CGFloat {
        onEdit == nil ? actionWidth : actionWidth * 2
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Action buttons sit BEHIND the row, only visible when
            // the row offsets left. When both Edit + Close are
            // wired, they sit side-by-side (Edit on left, Close on
            // right), matching iOS swipe-actions convention.
            HStack(spacing: 0) {
                if let onEdit {
                    Button(action: {
                        onEdit()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            offset = 0
                            open = false
                        }
                    }) {
                        Text("Edit")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: actionWidth)
                            .frame(maxHeight: .infinity)
                            .background(Color.theme.fg2)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: {
                    onClose()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        offset = 0
                        open = false
                    }
                }) {
                    Text("Close")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: actionWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.theme.neg)
                }
                .buttonStyle(.plain)
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.theme.surface)   // opaque cover
                .offset(x: offset)
                // Tap-anywhere-on-row dismisses the open drawer.
                // Falls through (no effect) when the row isn't
                // open — so normal interactions inside the row
                // aren't intercepted.
                .onTapGesture {
                    if open {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            offset = 0
                            open = false
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30)
                        .onChanged { v in
                            let dx = v.translation.width
                            let dy = v.translation.height
                            // Engage only on clearly horizontal motion.
                            // Direction depends on current state:
                            //   • Closed → only LEFTWARD opens it.
                            //   • Open → only RIGHTWARD closes it.
                            // That way a vertical scroll never triggers
                            // either direction.
                            guard abs(dx) > abs(dy) * 2.5 else { return }
                            if open {
                                guard dx > 10 else { return }
                            } else {
                                guard dx < -10 else { return }
                            }
                            let base = open ? -revealWidth : 0
                            offset = max(-revealWidth, min(0, base + dx))
                        }
                        .onEnded { _ in
                            // Only snap if the user actually moved
                            // the row (i.e. our onChanged engaged).
                            guard offset != 0 || open else { return }
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                let shouldOpen = offset < -revealWidth / 2
                                open = shouldOpen
                                offset = shouldOpen ? -revealWidth : 0
                            }
                        }
                )
        }
        .clipped()
    }
}
