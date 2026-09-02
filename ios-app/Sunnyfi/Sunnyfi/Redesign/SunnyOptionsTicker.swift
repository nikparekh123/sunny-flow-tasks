//
//  SunnyOptionsTicker.swift
//  Sunny — the three option cards on a name's own page.
//
//  Build sheet: OPTIONS-CARDS.md, Parts 3 and 4. Order is fixed: weekly credit,
//  the pair in THIS WEEK scope, pace to cover.
//
//  ⚠ ONLY `THIS WEEK` RENDERS. The sheet contradicts itself — Part 1 §2 says
//  three cards with the pair in THIS WEEK, Part 4 §11 says both scopes render
//  stacked, which is four. Nik ruled three on 2026-09-02. SINCE OPEN is built
//  in the same view and reachable by passing `.life`; nothing renders it today.
//

import SwiftUI

// MARK: - shared

private struct TCard<Content: View>: View {
    let name: String
    @ViewBuilder let body_: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { body_() }
            /* ⚠ 361 IS A FLOOR, NOT A CEILING, AND THAT IS THE WHOLE FIX.
               `.frame(height:)` PROPOSES a height, it does not clamp one. Every
               fixed card measured OVER its 322 content box — yield-progress by
               33.7, pair-week 21.7, pace-ahead 18.0, name-credit 12.3,
               weekly-yield 8.0 — so the content ran past the box, ate all 22pt
               of bottom padding, and on yield-progress was CLIPPED 11.7pt below
               the card edge. The one card that measured right was the rows form,
               and it measured right because it was free-height.

               The 361 came off CSS, where line-height IS the line advance.
               SwiftUI gives every Text its own leading on top of that, so the
               same content lays out taller here and no padding number could
               have made it fit. `minHeight` keeps 361 for a card whose content
               fits and lets the rest grow, so the footer sits 22 off the floor
               on all six. Cards now vary in height with the size of the book. */
            .frame(width: S.content - 38, alignment: .top)
            .frame(minHeight: 361 - 39, alignment: .top)
            /* ⚠ 22 AT THE BOTTOM, NOT THE SHEET'S 16. The sheet measured
               --pad-card-m off CSS, where a 19px figure at line-height 1 sits
               its baseline flush to the box floor. SwiftUI gives Text its own
               leading, so the same 16 left the footer figures visually touching
               the card edge on every card. The extra 6 comes out of the slack
               row, so the card still measures 361. */
            .padding(EdgeInsets(top: 17, leading: 19, bottom: 22, trailing: 19))
            .frame(width: S.content, alignment: .top)
            .background(S.paper)
            .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
            .sunnyShadow(S.shadowCard)
            .monospacedDigit()
            .measure(name)
    }
}

private struct TFooter: View {
    struct Stat { let label: String; let value: String; let ink: Color }
    let stats: [Stat]
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(S.ruleColor).frame(height: 1)
            Spacer().frame(height: 13)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.offset) { i, s in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(s.label.uppercased())
                            .font(S.inter(S.t10, S.wBoldN))
                            .tracking(S.track(S.t10, S.lsLabel))
                            .foregroundStyle(S.mute).lineLimit(1)
                        Text(s.value)
                            .font(S.inter(S.t19, S.wBoldN))
                            .tracking(S.track(S.t19, -0.025))
                            .foregroundStyle(s.ink).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, i == 0 ? 0 : S.statRulePad)
                }
            }
        }
    }
}

private struct THead: View {
    let ticker: String, sub: String
    var right: String? = nil
    var scope: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text(ticker).font(S.inter(S.t14, S.wBoldN))
                    .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                Text(sub).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            Spacer(minLength: 0)
            HStack(spacing: S.gap4) {
                if let scope {
                    Text(scope.uppercased())
                        .font(S.inter(S.t10, S.wBoldN))
                        .tracking(S.track(S.t10, S.lsLabel))
                        .foregroundStyle(S.mute)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(S.wash))
                }
                if let right {
                    Text(right).font(S.inter(S.t12, S.wMidSmN))
                        .foregroundStyle(S.ink2).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - 1 · weekly credit, one name

/// The book's weekly-yield device in dollars rather than percent. Same rule:
/// a rate takes no direction ink, so every bar is grey but the live week.
struct SunnyNameCredit: View {
    let p: OptionsPosition

    private var maxV: Double { max(Double(p.weekly.map(abs).max() ?? 1), 1) }
    /* ⚠ DIVIDE BY THE WEEKS THAT RAN, not by the window. FIS and PEP have
       two live weeks of eight, so an eight-week divisor understates them
       fourfold. The bars still show all eight. */
    private var avg: Double { Double(p.windowCredit) / Double(max(p.liveWeeks, 1)) }

    var body: some View {
        TCard(name: "name-credit") {
            THead(ticker: p.t, sub: "weekly credit", right: p.leap)
            Spacer().frame(height: S.gap7)
            VStack(alignment: .leading, spacing: 5) {
                Text("AVERAGE, \(p.liveWeeks) OF \(p.weekly.count) WEEKS RUN")
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                HStack(alignment: .firstTextBaseline, spacing: S.gap3) {
                    Text(optMoney(Int(avg.rounded())))
                        .font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.03))
                        .foregroundStyle(S.ink).sunnyLineBox(S.t30)
                    Text("a week").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
                }
            }
            Spacer().frame(height: 18)
            plot
            Spacer().frame(height: S.gap4)
            labels
            Spacer(minLength: S.gap6)
            TFooter(stats: [
                .init(label: "Paid back",
                      value: String(format: "%.1f%%",
                                    p.paid > 0 ? Double(p.collected) / Double(p.paid) * 100 : 0),
                      ink: S.ink),
                .init(label: "Collected", value: optMoney(p.collected), ink: S.gain),
                /* Weeks to the LEAP's expiry at the current average. Not a
                   forecast, and it says "covers in" rather than "will cover". */
                .init(label: "Covers in",
                      value: avg > 0 ? "\(Int((Double(p.paid - p.collected) / avg).rounded()))w" : "\u{2014}",
                      ink: S.ink),
            ])
        }
    }

    private var plot: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(S.ruleColor).frame(height: 1)
            HStack(alignment: .bottom, spacing: S.gap4) {
                ForEach(Array(p.weekly.enumerated()), id: \.offset) { i, v in
                    let live = i == p.weekly.count - 1
                    UnevenRoundedRectangle(topLeadingRadius: S.radiusBar,
                                           bottomLeadingRadius: 1, bottomTrailingRadius: 1,
                                           topTrailingRadius: S.radiusBar)
                        .fill(live ? S.gainBar : S.barQuiet)
                        .frame(maxWidth: S.weekBarMax)
                        .frame(height: max(1, S.weekPlotH * Double(abs(v)) / maxV))
                }
            }
            Rectangle().fill(S.ink).frame(height: S.refLine)
                .offset(y: -S.weekPlotH * avg / maxV)
        }
        .frame(height: S.weekPlotH, alignment: .bottom)
    }

    private var labels: some View {
        HStack(spacing: S.gap4) {
            ForEach(Array(p.weekly.enumerated()), id: \.offset) { i, _ in
                let live = i == p.weekly.count - 1
                /* ⚠ COUNT FORWARD, NOT BACK FROM weeksRun. The sheet labels
                   these with the position's real week numbers, which assumes
                   the window sits inside its life. FIS has run ONE week, so
                   counting back eight printed −6, −5, −4 … and a negative week
                   is not a thing. W1…W8 names the window, which is what the
                   axis actually is, and matches the book card. */
                Text("W\(i + 1)")
                    .font(S.inter(S.t12, live ? S.wBoldN : S.wMidSmN))
                    .foregroundStyle(live ? S.ink : S.mute)
                    .frame(maxWidth: S.weekBarMax).lineLimit(1)
            }
        }
    }
}

// MARK: - 2 · the pair

/// ⚠ THE TWO LEGS ARE ONE TRADE, SO ONLY THE NET IS A RESULT. The net is the
/// hero; the legs are bars beneath it. A short call losing money means the
/// stock ran, which is the same week the LEAP gains — read the short leg alone
/// and a good week looks like a bad one. This card exists because that
/// misreading is easy and expensive.
///
/// ⚠ THE VERDICT WORD IS GREY. Action colour belongs to the roll check, which
/// is where you triage. A green "next expiry" beside a red net reads as the
/// card arguing with itself.
struct SunnyPair: View {
    enum Scope { case week, life }
    let p: OptionsPosition
    var scope: Scope = .week

    private var short: OptionsPosition.ShortLeg? { p.shorts.first }
    private var legs: [(v: Int, label: String)] {
        switch scope {
        case .week:
            let callPL = p.shorts.reduce(0) { $0 + ($1.credit - $1.value) }
            return [(callPL, "Call sold"), (p.markWeek, "Long LEAP")]
        case .life:
            return [(p.collected, "Credits kept"), (p.mark - p.paid, "LEAP mark")]
        }
    }
    private var net: Int { legs.reduce(0) { $0 + $1.v } }
    private var rolling: Bool { p.shorts.contains(where: \.itm) }

    var body: some View {
        TCard(name: "pair-\(scope == .week ? "week" : "life")") {
            THead(ticker: p.t, sub: "the pair",
                  right: scope == .week ? (short?.contract ?? p.leap) : p.leap,
                  scope: scope == .week ? "This week" : "Since open")
            Spacer().frame(height: S.gap6)
            VStack(alignment: .leading, spacing: 5) {
                Text(scope == .week ? "NET, BOTH LEGS" : "NET SINCE OPEN")
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                HStack(alignment: .firstTextBaseline, spacing: S.gap5) {
                    Text(optMoney(net))
                        .font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.03))
                        .foregroundStyle(net < 0 ? S.loss : S.gain).sunnyLineBox(S.t30)
                    Text(scope == .week
                         ? (rolling ? "ROLL UP AND OUT" : "MOVE TO NEXT EXPIRY")
                         : "\(p.weeksRun) WEEKS IN")
                        .font(S.inter(S.t11, S.wBoldN))
                        .tracking(S.track(S.t11, S.lsTag))
                        .lineSpacing(S.t11 * 0.25)
                        .foregroundStyle(S.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer().frame(height: 18)
            plot
            Spacer().frame(height: S.gap5)
            legLabels
            /* ⚠ THE SHEET'S RHYTHM PUTS 12pt OF SLACK BETWEEN THE LEG LABELS
               AND THE FOOTER RULE, and `Spacer(minLength: 0)` collapsed it to
               nothing whenever the card was already full, so "Call sold" and
               "Long LEAP" sat on the line. */
            Spacer(minLength: 12)
            TFooter(stats: footerStats)
        }
    }

    private var footerStats: [TFooter.Stat] {
        let delta = TFooter.Stat(label: "Net delta",
                                 value: (p.netDelta > 0 ? "+" : p.netDelta < 0 ? "\u{2212}" : "")
                                      + "\(abs(p.netDelta))",
                                 ink: S.ink)
        if scope == .week {
            return [
                .init(label: "Captured",
                      value: short.map { "\($0.captured > 0 ? "+" : "")\($0.captured)%" } ?? "\u{2014}",
                      ink: (short?.captured ?? 0) < 0 ? S.loss : S.gain),
                delta,
                .init(label: "Shares", value: "\(p.longN * 100)", ink: S.ink),
            ]
        }
        /* ⚠ YEARLY IS ON THIS SCOPE ONLY. It is the one window with enough
           weeks behind it for a yearly rate to mean anything. */
        let yearly = p.paid > 0 && p.weeksRun > 0
            ? Double(p.collected) / Double(p.weeksRun) * 52 / Double(p.paid) * 100 : 0
        return [
            .init(label: "Paid back",
                  value: String(format: "%.1f%%",
                                p.paid > 0 ? Double(p.collected) / Double(p.paid) * 100 : 0),
                  ink: S.ink),
            delta,
            .init(label: "Yearly", value: String(format: "%.0f%%", yearly), ink: S.ink),
        ]
    }

    /// A SIGNED plot: zero sits where the data puts it. Up bars offset from the
    /// plot bottom, down bars from the top — the same rule, and the same bug,
    /// as the roll check.
    private var plot: some View {
        let vals = legs.map { CGFloat($0.v) }
        let up = max(0, vals.max() ?? 0) * 1.12
        let down = max(0, -(vals.min() ?? 0)) * 1.12
        let k = S.pairPlotH / max(up + down, 1)
        let zero = up * k
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(S.ruleColorStrong).frame(height: 1).offset(y: zero)
            HStack(spacing: S.pairColGap) {
                ForEach(Array(legs.enumerated()), id: \.offset) { _, l in
                    let v = CGFloat(l.v), h = abs(v) * k
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        UnevenRoundedRectangle(
                            topLeadingRadius: v >= 0 ? S.radiusBar : 1,
                            bottomLeadingRadius: v >= 0 ? 1 : S.radiusBar,
                            bottomTrailingRadius: v >= 0 ? 1 : S.radiusBar,
                            topTrailingRadius: v >= 0 ? S.radiusBar : 1)
                            .fill(l.v < 0 ? S.lossBar : S.gainBar)
                            .frame(width: S.pairBarW, height: max(h, 1))
                            .offset(y: v >= 0 ? zero - h : zero)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: S.pairPlotH)
    }

    private var legLabels: some View {
        HStack(spacing: S.pairColGap) {
            ForEach(Array(legs.enumerated()), id: \.offset) { _, l in
                VStack(spacing: S.gap3) {
                    Text(optMoney(l.v))
                        .font(S.inter(S.t13, S.wSemiN))
                        .foregroundStyle(l.v < 0 ? S.lossText : S.gainText).lineLimit(1)
                    Text(l.label)
                        .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - 3 · pace to cover

/// ⚠ THE Y AXIS TOP IS THE PREMIUM PAID, so the grey line landing in the
/// top-right corner means "covered exactly at expiry". The x axis is the
/// position's whole life.
///
/// ⚠ THE GREY LINE IS STRAIGHT AND THAT IS NOT AN OVERSIGHT. It is the premium
/// divided by weeks to expiry: a TARGET RAMP, not a measured series. The
/// measured alternative, the book average at the same point in each position's
/// life, is a different card and is not built.
struct SunnyPace: View {
    let p: OptionsPosition

    private var total: Int { p.weeksRun + p.weeksLeft }
    private var needed: Int { Int(Double(p.paid) * Double(p.weeksRun) / Double(max(total, 1))) }
    private var ahead: Bool { p.collected >= needed }
    private var ink: Color { ahead ? S.gain : S.loss }

    /// The cumulative series, which must end at `collected` — the sheet's
    /// invariant, and the reason a negative week has to dip the curve rather
    /// than be clamped away.
    private var curve: [CGFloat] {
        var run = 0, out: [CGFloat] = [0]
        for v in p.weekly { run += v; out.append(CGFloat(run)) }
        return out
    }

    var body: some View {
        TCard(name: ahead ? "pace-ahead" : "pace-behind") {
            THead(ticker: p.t, sub: "pace to cover")
            Spacer().frame(height: S.gap6)
            Text(sentence)
                .font(S.inter(17, S.wBoldN)).tracking(S.track(17, -0.02))
                .lineSpacing(17 * 0.3).foregroundStyle(S.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: S.gap7)
            Rectangle().fill(S.ruleColor).frame(height: 1)
            Spacer().frame(height: S.gap7)
            legend
            Spacer().frame(height: 18)
            chart
            Spacer().frame(height: S.gap4)
            axis
            Spacer(minLength: 0)
        }
    }

    private var sentence: String {
        let pct = p.paid > 0 ? Double(p.collected) / Double(p.paid) * 100 : 0
        return ahead
            ? "\(optMoney(p.collected)) collected, \(String(format: "%.0f", pct))% of the LEAP, and ahead of the pace it needs."
            : "\(optMoney(p.collected)) collected, \(String(format: "%.0f", pct))% of the LEAP, and behind the pace it needs."
    }

    private var legend: some View {
        HStack(alignment: .top, spacing: S.gap7) {
            legendBlock("Collected", optMoney(p.collected), ink)
            legendBlock("Needed by now", optMoney(needed), S.mute, dot: S.hair)
        }
    }

    private func legendBlock(_ l: String, _ v: String, _ c: Color, dot: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: S.gap4) {
            HStack(spacing: S.gap3) {
                Circle().fill(dot ?? c).frame(width: S.paceDot, height: S.paceDot)
                Text(l.uppercased())
                    .font(S.inter(S.t12, S.wBoldN)).tracking(S.track(S.t12, S.lsLabel))
                    .foregroundStyle(c).lineLimit(1)
            }
            Text(v).font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.025))
                .foregroundStyle(c).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        GeometryReader { g in
            let w = g.size.width, h = S.paceH
            let top = CGFloat(max(p.paid, 1))
            let x = { (i: Int) in w * CGFloat(i) / CGFloat(max(total, 1)) }
            let y = { (v: CGFloat) in h - h * v / top }
            ZStack(alignment: .topLeading) {
                // the target ramp: straight, because it is a target
                Path { pt in
                    pt.move(to: CGPoint(x: 0, y: h))
                    pt.addLine(to: CGPoint(x: w, y: 0))
                }.stroke(S.hair, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                // "now"
                Path { pt in
                    pt.move(to: CGPoint(x: x(p.weeksRun), y: 0))
                    pt.addLine(to: CGPoint(x: x(p.weeksRun), y: h))
                }.stroke(S.barQuiet, lineWidth: 1.5)
                // the collected curve, through every week
                Path { pt in
                    for (i, v) in curve.enumerated() {
                        let point = CGPoint(x: x(max(0, p.weeksRun - curve.count + 1 + i)), y: y(v))
                        i == 0 ? pt.move(to: point) : pt.addLine(to: point)
                    }
                }.stroke(ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                Circle().fill(S.hair).frame(width: 9, height: 9).offset(x: w - 4.5, y: -4.5)
                Circle().fill(ink).frame(width: 9, height: 9)
                    .offset(x: x(p.weeksRun) - 4.5, y: y(CGFloat(p.collected)) - 4.5)
            }
        }
        .frame(height: S.paceH)
    }

    private var axis: some View {
        HStack {
            Text("OPEN").font(S.inter(S.t11, S.wBoldN))
                .tracking(S.track(S.t11, S.lsLabel)).foregroundStyle(S.mute)
            Spacer()
            Text("WK \(p.weeksRun)").font(S.inter(S.t11, S.wBoldN))
                .tracking(S.track(S.t11, S.lsLabel)).foregroundStyle(S.ink)
            Spacer()
            Text(String(p.leap.split(separator: "·").last ?? "").trimmingCharacters(in: .whitespaces).uppercased())
                .font(S.inter(S.t11, S.wBoldN))
                .tracking(S.track(S.t11, S.lsLabel)).foregroundStyle(S.mute)
        }
    }
}

/// ⚠ THE PAGE FIGURES, FROM THE OPTIONS BOOK. `PNL_GLOSSARY.md`: UNREALIZED is
/// open legs only, REALIZED is closed only, NET is both. So CURRENT is the
/// LEAP's mark against its cost plus every OPEN short's credit against its
/// value, and TOTAL adds the credits already banked on legs since closed —
/// which is `collected` less the credit still sitting on open legs.
func optCurrent(_ p: OptionsPosition) -> Int {
    (p.mark - p.paid) + p.shorts.reduce(0) { $0 + ($1.credit - $1.value) }
}

func optTotal(_ p: OptionsPosition) -> Int {
    let openCredit = p.shorts.reduce(0) { $0 + $1.credit }
    return optCurrent(p) + (p.collected - openCredit)
}
