//
//  NvdaPlannerScreen.swift
//  Sunnyfi — Ink rebuild · Planner
//
//  Faithful SwiftUI port of the shipped NVDA Planner page (ink-planner-page.jsx +
//  ink-planner-commit.jsx, the `.pg-*` design). Six sections — Gate, Guardrails,
//  Which expiry, Which strike, What happens next, Calibration — over a sticky
//  Commit bar. All pricing is computed by the `nvda-planner` edge function; this
//  view renders the returned state and re-calls the function on each interaction.
//
//  Ink Law 1 holds: hue only on money/probability data — PG_UP = gain (blue),
//  PG_DOWN = loss (orange); chrome is monochrome; selection is inversion.
//

import SwiftUI

// MARK: - Palette + formatting (the `.pg-*` helpers)

private let PG_UP = Ink.gain          // var(--ink-peril-flood)
private let PG_DOWN = Ink.loss        // var(--ink-peril-fire)

private func pgUsd(_ n: Double) -> String {
    (n < 0 ? "−$" : "$") + Int(abs(n).rounded()).formatted(.number.grouping(.automatic))
}
private func pgSigned(_ n: Double, _ dp: Int = 2) -> String {
    (n < 0 ? "−$" : "+$") + String(format: "%.\(dp)f", abs(n))
}
private func pgMoney(_ n: Double) -> String {   // commit-cell signed money, grouped, 0dp
    (n < 0 ? "−$" : "+$") + Int(abs(n).rounded()).formatted(.number.grouping(.automatic))
}
private func grp(_ n: Double) -> String { Int(n.rounded()).formatted(.number.grouping(.automatic)) }
private func signedInt(_ n: Double) -> String { (n >= 0 ? "+" : "−") + grp(abs(n)) }

/// Uppercase mono label (pgM). `tracking` is em-relative, matching the CSS.
private func M(_ text: String, _ size: CGFloat, _ ls: CGFloat = 0.14, _ color: Color = Ink.dim, upper: Bool = true) -> Text {
    Text(upper ? text.uppercased() : text).font(InkFont.mono(size)).tracking(size * ls).foregroundStyle(color)
}
/// Mono number (pgN) — tight tracking, full ink by default.
private func N(_ text: String, _ size: CGFloat, _ color: Color = Ink.text) -> Text {
    Text(text).font(InkFont.mono(size)).tracking(size * -0.02).foregroundStyle(color)
}

private let CONV_LABEL = ["expiry": "at expiry", "half": "halfway", "t1": "t+1"]
private let CONV_NOTE = [
    "expiry": "held to expiry, so option value is intrinsic",
    "half": "clock advanced half the holding period",
    "t1": "one trading day from now",
]
private let PL_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// MARK: - Screen shell

struct NvdaPlannerScreen: View {
    let store: NvdaStore
    let onClose: () -> Void
    @State private var planner = PlannerStore()

    var body: some View {
        ZStack(alignment: .bottom) {
            Ink.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                nav
                content
            }
            if let s = planner.state {
                CommitBarView(planner: planner, s: s)
            }
        }
        .task { await planner.load(from: store) }
    }

    private var nav: some View {
        HStack(spacing: 13) {
            Button(action: onClose) {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .regular)).foregroundStyle(Ink.text)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(Ink.hair, lineWidth: 1))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                M("NVDA · next short call", 9, 0.18)
                Text("Planner").font(InkFont.serif(27)).tracking(27 * -0.01).foregroundStyle(Ink.text).padding(.top, 9)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 18, leading: 16, bottom: 16, trailing: 16))
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }

    @ViewBuilder private var content: some View {
        if let s = planner.state {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GateSectionView(s: s)
                    GuardrailsView(planner: planner)
                    ExpirySectionView(planner: planner, s: s)
                    LadderSectionView(planner: planner, s: s)
                    ScenarioSectionView(planner: planner, s: s)
                    CalibrationSectionView(log: planner.log)
                    Color.clear.frame(height: 268)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(planner.isLoading ? 0.55 : 1)
            .animation(InkMotion.fast, value: planner.isLoading)
        } else if planner.lastError != nil {
            quiet("Planner unavailable", planner.lastError ?? "")
        } else {
            VStack { Spacer(); ProgressView().tint(Ink.dim); Spacer() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func quiet(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            M(t, 10, 0.16); Text(b).font(InkFont.display(12.5, .light)).foregroundStyle(Ink.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16).padding(.top, 60)
    }
}

// MARK: - Section container (.pg-sect)

struct PGSection<Content: View>: View {
    let n: String
    let title: String
    var right: AnyView? = nil
    var first: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    M("Section \(n)", 9, 0.18)
                    Text(title).font(InkFont.serif(24)).tracking(24 * -0.01).foregroundStyle(Ink.text).padding(.top, 9)
                }
                Spacer(minLength: 0)
                if let right { right }
            }
            .padding(.bottom, 16)
            content()
        }
        .padding(.top, 26).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Ink.hair).frame(height: 1) } }
    }
}

// A framed card block used across sections.
private func pgCard<V: View>(@ViewBuilder _ content: () -> V) -> some View {
    content()
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(.clear))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).strokeBorder(Ink.hair, lineWidth: 1))
}

// MARK: - 01 · Gate

struct GateSectionView: View {
    let s: PlannerState
    private var g: PGate { s.gate }
    private var pass: Bool { g.score >= 0.8 }

    var body: some View {
        PGSection(n: "01", title: "Gate",
                  right: AnyView(verdict), first: true) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(g.flags) { banner($0) }
                scoreCard.padding(.top, 5)
                grid6.padding(.top, 3)
                trend.padding(.top, 3)
                capacity.padding(.top, 3)
            }
        }
    }

    private var verdict: some View {
        M(g.blocked ? "Do not sell" : "Clear", 9, 0.14, g.blocked ? Ink.text : Ink.invertText)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background {
                if g.blocked { Capsule().strokeBorder(Ink.text, lineWidth: 1) }
                else { Capsule().fill(Ink.invertBg) }
            }
    }

    private func banner(_ f: PFlag) -> some View {
        let block = f.level == "block"
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                M(f.head, 9.5, 0.16, Ink.text); Spacer(minLength: 0)
                M(block ? "blocking" : "note", 8, 0.12)
            }
            Text(f.body).font(InkFont.display(12, .light)).foregroundStyle(Ink.dim).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
        .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(block ? Ink.text.opacity(0.04) : .clear))
        .overlay(alignment: .leading) {
            Rectangle().fill(block ? Ink.text : Ink.dim).frame(width: 2)
                .opacity(block ? 1 : 0.9)
        }
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
    }

    private var scoreCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                M("Seller score", 8.5, 0.16)
                InkRoll(text: String(format: "%.2f", g.score), font: InkFont.mono(38, .light),
                        color: pass ? PG_UP : PG_DOWN).padding(.top, 10)
                M("sell above 0.80", 8, 0.1).padding(.top, 9)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                mathRow("IV \(fmt1(g.iv))% ÷ HV30 \(fmt1(g.hv30))%", String(format: "%.3f", g.iv / max(g.hv30, 0.01)))
                mathRow("× percentile \(Int(g.ivPct.rounded())) factor", String(format: "%.1f", g.pctFactor))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { Rectangle().fill(Ink.hair).frame(width: 1) }
            .padding(.leading, 14)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
    }
    private func mathRow(_ l: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            M(l, 9, 0.06); Spacer(minLength: 0); N(v, 12)
        }
    }

    private var grid6: some View {
        let cells: [(String, String, String?)] = [
            ("Spot", "$\(fmt2(g.spot))", nil), ("Implied", "\(fmt1(g.iv))%", "pctile \(Int(g.ivPct.rounded()))"),
            ("HV 30", "\(fmt1(g.hv30))%", nil), ("HV 60", "\(fmt1(g.hv60))%", nil),
            ("HV 90", "\(fmt1(g.hv90))%", nil), ("Earnings", "\(g.daysToEarnings)d", g.earnings),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                VStack(alignment: .leading, spacing: 6) {
                    M(c.0, 8, 0.14)
                    N(c.1, 17).padding(.top, 2)
                    if let sub = c.2 { M(sub, 7.5, 0.1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 13, leading: 12, bottom: 14, trailing: 12))
                .background(Ink.canvas)
            }
        }
        .background(Ink.hair)
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
    }

    private var trend: some View {
        let expanding = g.hvTrend == "expanding"
        let txt: String = g.hvTrend == "stable"
            ? "Realized vol is stable across lookbacks."
            : "Realized vol is \(g.hvTrend). HV30 sits \(fmt1(g.hvGap)) pts \(expanding ? "above" : "below") HV90, so the score is measured at a local \(expanding ? "high" : "low")."
        return HStack(alignment: .top, spacing: 8) {
            if g.hvTrend != "stable" {
                Text(expanding ? "▲" : "▼").font(.system(size: 11)).foregroundStyle(expanding ? PG_DOWN : PG_UP)
            }
            Text(txt).font(InkFont.display(11.5, .light)).foregroundStyle(Ink.dim).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
    }

    private var capacity: some View {
        let b = s.book
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                M("Contracts", 9, 0.16); Spacer(minLength: 0); N("\(Int(b.capacity)) ct", 20)
            }
            HStack(spacing: 10) {
                M("\(grp(b.shares)) sh ÷ 100", 8, 0.1)
                Spacer(minLength: 0)
                M("\(Int(b.shortCallCt)) ct written · rolls into the next sale", 8, 0.1, Ink.text)
            }
        }
        .padding(EdgeInsets(top: 15, leading: 16, bottom: 16, trailing: 16))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
    }
}

// MARK: - Guardrails panel

struct GuardrailsView: View {
    @Bindable var planner: PlannerStore
    private var st: PlannerSettings { planner.settings }

    private var summary: String {
        PlannerSettings.order.map { st.summaryFmt($0) }.joined(separator: "  ·  ")
    }
    private var dirtyCount: Int {
        PlannerSettings.order.filter { st.summaryFmt($0) != PlannerSettings.default.summaryFmt($0) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(InkMotion.fast) { planner.guardsOpen.toggle() } } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        M("Guardrails", 9, 0.16, Ink.text)
                        M(summary, 8.5, 0.08, Ink.dim, upper: false)
                    }
                    Spacer(minLength: 0)
                    if dirtyCount > 0 {
                        M("\(dirtyCount) changed", 7.5, 0.12, PG_DOWN)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(PG_DOWN.opacity(0.16)))
                    }
                    Text(planner.guardsOpen ? "−" : "+").font(InkFont.mono(13)).foregroundStyle(Ink.dim)
                        .frame(width: 26, height: 26).overlay(Circle().strokeBorder(Ink.hair, lineWidth: 1))
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            }.buttonStyle(.plain)

            if planner.guardsOpen {
                rowsView
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
        .padding(.top, 22).padding(.bottom, 4)
    }

    @ViewBuilder private var rowsView: some View {
        guardRow("minNetDelta")
        guardRow("maxAssign")
        guardRow("edgeFloor")
        guardRow("weekendVol")
        guardRow("edgeLookback")
        HStack(alignment: .firstTextBaseline) {
            M("Dot marks the default", 8, 0.1)
            Spacer(minLength: 0)
            Button { planner.resetSettings() } label: {
                M("Reset to defaults", 8.5, 0.14, dirtyCount > 0 ? Ink.text : Ink.dim)
                    .padding(.horizontal, 13).frame(minHeight: 32)
                    .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
            }.buttonStyle(.plain).disabled(dirtyCount == 0).opacity(dirtyCount == 0 ? 0.5 : 1)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }

    @ViewBuilder private func guardRow(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                M(PlannerSettings.labels[key] ?? key, 8.5, 0.14)
                Spacer(minLength: 0)
                let changed = st.summaryFmt(key) != PlannerSettings.default.summaryFmt(key)
                N(st.summaryFmt(key), 13, changed ? PG_DOWN : Ink.text)
            }
            segmented(key)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }

    @ViewBuilder private func segmented(_ key: String) -> some View {
        switch key {
        case "minNetDelta":
            seg(PlannerSettings.deltaOpts, cur: st.minNetDelta, def: PlannerSettings.default.minNetDelta,
                fmt: PlannerSettings.fmtDelta) { v in planner.setSetting { $0.minNetDelta = v } }
        case "maxAssign":
            seg(PlannerSettings.assignOpts, cur: st.maxAssign, def: PlannerSettings.default.maxAssign,
                fmt: PlannerSettings.fmtAssign) { v in planner.setSetting { $0.maxAssign = v } }
        case "edgeFloor":
            seg(PlannerSettings.edgeOpts, cur: st.edgeFloor, def: PlannerSettings.default.edgeFloor,
                fmt: PlannerSettings.fmtEdge) { v in planner.setSetting { $0.edgeFloor = v } }
        case "weekendVol":
            seg(PlannerSettings.weekendOpts, cur: st.weekendVol, def: PlannerSettings.default.weekendVol,
                fmt: PlannerSettings.fmtWeekend) { v in planner.setSetting { $0.weekendVol = v } }
        default:
            seg(PlannerSettings.lookbackOpts, cur: st.edgeLookback, def: PlannerSettings.default.edgeLookback,
                fmt: PlannerSettings.fmtLookback) { v in planner.setSetting { $0.edgeLookback = v } }
        }
    }

    private func seg<T: Equatable>(_ opts: [T], cur: T, def: T, fmt: @escaping (T) -> String, pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(opts.enumerated()), id: \.offset) { i, v in
                let on = v == cur
                Button { pick(v) } label: {
                    ZStack(alignment: .bottom) {
                        M(fmt(v), 10.5, -0.01, on ? Ink.invertText : Ink.dim, upper: false)
                            .frame(maxWidth: .infinity, minHeight: 36)
                        if v == def { Circle().fill(on ? Ink.invertText.opacity(0.6) : Ink.dim).frame(width: 3, height: 3).padding(.bottom, 5) }
                    }
                    .background(on ? Ink.invertBg : .clear)
                    .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Ink.hair).frame(width: 1) } }
                }.buttonStyle(.plain)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusElement))
    }
}

// MARK: - Shared small pieces

private func pgTag(_ text: String, style: Int = 0) -> some View {
    // style 0 = solid invert, 1 = outline, 2 = muted, 3 = baseline chip
    let fg: Color = style == 0 ? Ink.invertText : (style == 3 ? Ink.text : (style == 1 ? Ink.text : Ink.dim))
    let size: CGFloat = style == 3 ? 7 : 7.5
    return M(text, size, 0.14, fg)
        .padding(.horizontal, style == 0 ? 7 : 6).padding(.vertical, style == 0 ? 3 : 2)
        .background {
            if style == 0 { Capsule().fill(Ink.invertBg) }
            else if style == 3 { Capsule().fill(Ink.text.opacity(0.12)) }
            else { Capsule().strokeBorder(style == 1 ? Ink.text : Ink.hair, lineWidth: 1) }
        }
}

private func fmt1(_ v: Double) -> String { String(format: "%.1f", v) }
private func fmt2(_ v: Double) -> String { String(format: "%.2f", v) }
private func fmt0(_ v: Double) -> String { String(format: "%.0f", v) }
private func nvStrikeStr(_ k: Double) -> String { k == k.rounded() ? String(Int(k)) : String(format: "%.1f", k) }
private func pctLabel(_ p: Double) -> String {
    let a = abs(p)
    let s = a == a.rounded() ? String(Int(a)) : String(format: "%g", a)
    return "\(p > 0 ? "+" : p < 0 ? "−" : "±")\(s)%"
}
private func span(_ hi: Double, _ lo: Double, pct: Bool = false) -> String {
    let u = pct ? "%" : ""
    return "\(hi >= 0 ? "+" : "−")\(fmt0(abs(hi)))\(u) to \(lo >= 0 ? "+" : "−")\(fmt0(abs(lo)))\(u)"
}

// MARK: - 02 · Which expiry

struct ExpirySectionView: View {
    @Bindable var planner: PlannerStore
    let s: PlannerState

    private var best: PExpiry? { s.expiries.max { $0.perDay < $1.perDay } }
    private var maxPerDay: Double { s.expiries.map { $0.perDay }.max() ?? 1 }

    var body: some View {
        PGSection(n: "02", title: "Which expiry",
                  right: AnyView(M("\(Int(s.book.capacity)) ct", 8.5, 0.14))) {
            VStack(alignment: .leading, spacing: 0) {
                refStrip.padding(.bottom, 14)
                VStack(spacing: 8) { ForEach(s.expiries) { row($0) } }
                if (best?.we ?? 0) > 0 {
                    caveat("Edge depends on the weekend vol assumption (\(fmt1(planner.settings.weekendVol)) day). A weekend gap breaks it, and 1 DTE is peak gamma.")
                }
                method("Ranked by premium per trading day.")
            }
        }
    }

    private var refStrip: some View {
        var strikes: [Double] = []
        var k = s.refStrike - 5
        while k <= s.refStrike + 7.5 + 1e-9 { strikes.append(k); k += 2.5 }
        return VStack(alignment: .leading, spacing: 9) {
            M("Reference strike", 8.5, 0.14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(strikes, id: \.self) { kk in
                        let on = abs(kk - s.refStrike) < 1e-6
                        Button { planner.setRef(kk) } label: {
                            Text(nvStrikeStr(kk)).font(InkFont.mono(10.5)).tracking(10.5 * -0.01)
                                .foregroundStyle(on ? Ink.invertText : Ink.dim)
                                .padding(.horizontal, 12).frame(minHeight: 32)
                                .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(on ? Ink.invertBg : .clear))
                                .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(on ? .clear : Ink.hair, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ r: PExpiry) -> some View {
        let on = s.selExpiry == r.iso
        let win = best?.iso == r.iso
        return Button { planner.pickExpiry(r.iso) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    N(r.label, 15); M("\(r.dow) · \(r.cal)d", 8, 0.12)
                    if win { pgTag("best") }
                    Spacer(minLength: 0)
                    (N("$\(fmt2(r.perDay))", 16, win ? Ink.text : Ink.dim) + M(" /td", 7.5, 0.1))
                }
                bar(r.perDay / maxPerDay, win: win).padding(.vertical, 10)
                HStack(spacing: 9) {
                    M("$\(fmt2(r.prem))/sh", 8.5, 0.02); Spacer(minLength: 0)
                    M("\(pgUsd(r.credit)) credit", 8.5, 0.02); Spacer(minLength: 0)
                    M("\(Int((r.assign * 100).rounded()))% assign", 8.5, 0.02); Spacer(minLength: 0)
                    M("\(pgSigned(r.edge, 0)) edge", 8.5, 0.02, r.edge < 0 ? PG_DOWN : PG_UP)
                }
                M("\(r.td) td + \(r.we) we · \(fmt1(r.volDays)) vol-days", 8, 0.1).opacity(0.75).padding(.top, 7)
            }
            .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
            .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(on ? Ink.text.opacity(0.07) : .clear))
            .overlay(alignment: .leading) { Rectangle().fill(win || on ? Ink.text : .clear).frame(width: 2) }
            .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(on ? Ink.dim : Ink.hair, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func bar(_ frac: Double, win: Bool) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.hair)
                Capsule().fill(win ? Ink.text : Ink.dim).frame(width: max(0, min(1, frac)) * g.size.width)
            }
        }.frame(height: 6)
    }
}

// MARK: - 03 · Which strike (ladder)

struct LadderSectionView: View {
    @Bindable var planner: PlannerStore
    let s: PlannerState

    private var expiry: PExpiry? { s.expiries.first { $0.iso == s.selExpiry } ?? s.expiries.first }
    private var wall: Double { s.book.wall ?? .greatestFiniteMagnitude }
    private var wallIdx: Int? { s.chain.firstIndex { $0.strike >= wall } }

    var body: some View {
        let e = expiry
        PGSection(n: "03", title: "Which strike",
                  right: AnyView(M("\(e?.label ?? "") · \(e?.td ?? 0) td · \(planner.settings.edgeLookback.uppercased())", 8.5, 0.14))) {
            VStack(alignment: .leading, spacing: 0) {
                method("Premium is the objective. The guardrails are the only brake. Distance from spot is not safety.")
                    .padding(.bottom, 12)
                if s.recommendation.none { caveat(s.recommendation.why).padding(.bottom, 10) }
                VStack(spacing: 8) {
                    ForEach(Array(s.chain.enumerated()), id: \.element.strike) { i, r in
                        if wallIdx == i { wallDivider }
                        LadderRow(planner: planner, s: s, r: r)
                    }
                }
            }
        }
    }

    private var wallDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Ink.dim.opacity(0.55)).frame(height: 1)
            M("Long-call wall · $\(nvStrikeStr(wall)) · \(Int(s.book.longCallCt)) ct", 8, 0.14, Ink.text).fixedSize()
            Rectangle().fill(Ink.dim.opacity(0.55)).frame(height: 1)
        }
        .padding(.vertical, 3)
    }
}

struct LadderRow: View {
    @Bindable var planner: PlannerStore
    let s: PlannerState
    let r: PRung

    private var ct: Double { s.book.capacity }
    private var on: Bool { abs(s.selStrike - r.strike) < 1e-6 }
    private var isRec: Bool { !s.recommendation.none && (s.recommendation.strike.map { abs($0 - r.strike) < 1e-6 } ?? false) }
    private var otm: Double { (r.strike - s.gate.spot) / s.gate.spot * 100 }

    // Guard fails, recomputed client-side from the returned row + local settings.
    private var fails: [String] {
        let st = planner.settings
        var f: [String] = []
        if !r.sellable { f.append("sellable premium") }
        if r.netDeltaAfter < st.minNetDelta { f.append("min net delta") }
        if r.edgePct < st.edgeFloor { f.append("edge floor") }
        if r.assign > st.maxAssign { f.append("max assign") }
        return f
    }
    private var blockedRow: Bool { !fails.isEmpty }
    private var verdict: String? {
        if isRec { return s.gate.blocked ? "best avail" : "pick" }
        return blockedRow ? "blocked" : nil
    }

    var body: some View {
        Button { planner.pickStrike(r.strike) } label: {
            VStack(alignment: .leading, spacing: 0) {
                header
                grid.padding(.top, 12)
                if isRec { recBlock.padding(.top, 12) }
                if !fails.isEmpty { kink(fails.joined(separator: " · ")).padding(.top, 12) }
                else if on && r.advCost > 0 { kink("\(Int(r.affected)) of \(Int(ct)) ct sit below your $\(nvStrikeStr(s.book.wall ?? 0)) long calls").padding(.top, 12) }
            }
            .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
            .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(on ? Ink.text.opacity(0.07) : .clear))
            .overlay(alignment: .leading) { Rectangle().fill(isRec || on ? Ink.text : .clear).frame(width: 2) }
            .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(on ? Ink.dim : Ink.hair, lineWidth: 1))
            .opacity(blockedRow && !on ? 0.42 : 1)
        }.buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            N(nvStrikeStr(r.strike), 17)
            M("\(otm >= 0 ? "+" : "−")\(fmt1(abs(otm)))%", 8, 0.12)
            M(r.side, 8, 0.12)
            Spacer(minLength: 0)
            if let v = verdict { pgTag(v, style: v == "pick" ? 0 : (v == "best avail" ? 1 : 2)) }
            N("$\(fmt2(r.prem))", 15)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), spacing: 11) {
            cell("credit", pgUsd(r.prem * 100 * ct))
            cell("assign", "\(Int((r.assign * 100).rounded()))%")
            cell("edge", pgSigned(r.edge, 0), hue: r.edge < 0 ? PG_DOWN : PG_UP, sub: r.sellable ? span(r.edgeHi, r.edgeLo) : nil, cross: r.edgeCrosses)
            cell("of prem", r.sellable ? "\(r.edgePct < 0 ? "−" : "+")\(fmt0(abs(r.edgePct) * 100))%" : "—",
                 hue: !r.sellable ? Ink.dim : (r.edgePct < 0 ? PG_DOWN : PG_UP),
                 sub: r.sellable ? span(r.edgePctHi * 100, r.edgePctLo * 100, pct: true) : nil, cross: r.edgeCrosses)
            cell("net Δ after", signedInt(r.netDeltaAfter), hue: r.netDeltaAfter < 0 ? PG_DOWN : Ink.text)
            cell("% long", "\(Int((r.pctLong * 100).rounded()))%", hue: r.pctLong < 0 ? PG_DOWN : Ink.dim)
            cell("vs basis", pgSigned(r.vsBasis), hue: r.vsBasis < 0 ? PG_DOWN : PG_UP, sub: "eff $\(fmt2(r.effective))")
            cell("adv +15%", r.advCost > 0 ? "−$\(grp(r.advCost))" : "—", hue: r.advCost > 0 ? PG_DOWN : Ink.dim)
        }
    }

    private func cell(_ k: String, _ v: String, hue: Color = Ink.text, sub: String? = nil, cross: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            M(k, 7.5, 0.12)
            N(v, 10.5, hue)
            if let sub { M(sub, 7.5, 0.01, cross ? Ink.text : Ink.dim, upper: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recBlock: some View {
        let signals = s.signalsFor(r.strike)
        let bad = signals.filter { !$0.ok }
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(signals) { sg in
                        Circle().fill(sg.ok ? Ink.dim.opacity(0.55) : PG_DOWN).frame(width: 6, height: 6)
                    }
                }
                M("\(bad.count) of \(signals.count) signals negative", 9, 0.1, bad.count > 3 ? PG_DOWN : Ink.text)
                M(bad.map { $0.label.lowercased() }.joined(separator: " · "), 7.5, 0.1)
                    .lineLimit(1)
            }
            Text((s.recommendation.blocked ? "Gate is blocking. If you sell anyway: " : "") + s.recommendation.why)
                .font(InkFont.display(11.5, .light)).foregroundStyle(Ink.dim).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1).padding(.top, -11) }
    }

    private func kink(_ text: String) -> some View {
        M(text, 8.5, 0.1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1).padding(.top, -11) }
    }
}

// MARK: - 04 · What happens next (scenario)

struct ScenarioSectionView: View {
    @Bindable var planner: PlannerStore
    let s: PlannerState
    private var sc: PScenario { s.scenario }

    var body: some View {
        PGSection(n: "04", title: "What happens next",
                  right: AnyView(M("\(nvStrikeStr(s.selStrike)) · \(Int(s.book.capacity)) ct · \(CONV_LABEL[sc.conv] ?? "")", 8.5, 0.14))) {
            VStack(alignment: .leading, spacing: 0) {
                convSeg.padding(.bottom, 14)
                table
                given.padding(.top, 12)
                method2.padding(.top, 14)
            }
        }
    }

    private var convSeg: some View {
        HStack(spacing: 0) {
            ForEach(["expiry", "half", "t1"], id: \.self) { k in
                let on = sc.conv == k
                Button { planner.setConv(k) } label: {
                    M(CONV_LABEL[k] ?? k, 10.5, -0.01, on ? Ink.invertText : Ink.dim, upper: false)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Ink.invertBg : .clear)
                        .overlay(alignment: .leading) { if k != "expiry" { Rectangle().fill(Ink.hair).frame(width: 1) } }
                }.buttonStyle(.plain)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusElement))
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                M("short call", 7.5, 0.14).frame(maxWidth: .infinity, alignment: .leading)
                M("with the sale", 7.5, 0.14).frame(maxWidth: .infinity, alignment: .trailing)
                M("do nothing", 7.5, 0.14).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
            .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1) }
            ForEach(sc.steps) { scenRow($0) }
        }
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard))
    }

    private func scenRow(_ r: PScenStep) -> some View {
        let flat = r.p == 0
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(pctLabel(r.p))
                    .font(InkFont.mono(19)).tracking(19 * -0.03).foregroundStyle(flat ? Ink.dim : Ink.text)
                N("$\(fmt2(r.s))", 12, Ink.dim)
                if flat { pgTag("baseline", style: 3) }
                M(sc.conv == "expiry" ? "iv n/a" : "iv \(fmt1(r.ivUsed))", 8, 0.1)
                M("opt $\(fmt2(r.opt))", 8, 0.1)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                N(pgUsd(r.shortPl), 12, r.shortPl < 0 ? PG_DOWN : PG_UP).frame(maxWidth: .infinity, alignment: .leading)
                N(pgUsd(r.combined), 12.5, r.combined < 0 ? PG_DOWN : PG_UP).frame(maxWidth: .infinity, alignment: .trailing)
                N(pgUsd(r.sharePl), 12, Ink.dim).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
        .background(flat ? Ink.text.opacity(0.06) : .clear)
        .overlay(alignment: .top) { if r.p != sc.steps.first?.p { Rectangle().fill(Ink.hair).frame(height: 1) } }
    }

    private var given: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                M("Participation given up at +\(fmt0(sc.topPct))%", 9, 0.16)
                Spacer(minLength: 0)
                InkRoll(text: pgUsd(sc.givenUp), font: InkFont.mono(22, .light), color: sc.givenUp > 0 ? PG_DOWN : Ink.dim)
            }
            M("share P&L less combined at the top row", 8, 0.1)
        }
        .padding(EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
    }

    private var method2: some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text("Priced \(CONV_NOTE[sc.conv] ?? ""). IV response, \(sc.source.label). ")
                .font(InkFont.display(11.5, .light)).foregroundStyle(Ink.dim)
             + Text(sc.ivSource == "nvda" ? "use generic" : "use calibrated")
                .font(InkFont.display(11.5, .light)).foregroundStyle(Ink.text).underline())
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                .onTapGesture { planner.toggleSource() }
            Text("Down moves lift IV by \(fmt2(sc.source.down)) points per 1% decline, up moves ease it by \(fmt2(abs(sc.source.up))) per 1% rise (\(sc.source.note)). At expiry the IV path stops mattering, which is why holding to expiry is the honest default.")
                .font(InkFont.display(11, .light)).foregroundStyle(Ink.dim).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
        }
    }
}

// MARK: - 06 · Calibration

struct CalibrationSectionView: View {
    let log: [PlannerCycle]
    private var stx: PlannerCalStats { log.calStats }

    var body: some View {
        PGSection(n: "06", title: "Calibration",
                  right: AnyView(M("\(stx.n) settled", 8.5, 0.14))) {
            VStack(alignment: .leading, spacing: 0) {
                headline
                twoStats.padding(.top, 10)
                M("Predicted vs actual assignment", 9, 0.16).padding(.top, 22).padding(.bottom, 11)
                bucketsView
                Text("Buckets need \(PlannerLog.minN) settled cycles before they mean anything. \(stx.qualify) of \(stx.buckets.count) qualify.")
                    .font(InkFont.display(11.5, .light)).foregroundStyle(Ink.dim).padding(.top, 14)
                M("Recent cycles", 9, 0.16).padding(.top, 22).padding(.bottom, 11)
                logView
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            M("Average fill against mid", 9, 0.16)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                (InkRollText("\(stx.avgSlip < 0 ? "−" : "+")\(fmt1(abs(stx.avgSlip * 100)))", 34, stx.avgSlip < 0 ? PG_DOWN : PG_UP)
                 + N("¢", 34, stx.avgSlip < 0 ? PG_DOWN : PG_UP))
                M("per share", 8.5, 0.12)
            }.padding(.top, 11)
            HStack {
                N("\(pgUsd(stx.annual)) a year", 13, Ink.text)
                Spacer(minLength: 0)
                M("\(PlannerLog.cadence) cycles · \(fmt0(stx.avgCt)) ct average", 9, 0.06)
            }
            .padding(.top, 12).padding(.top, 1)
            .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
            .padding(.top, 12)
            Text("This is the biggest number on the page. It is larger than most of the strike decisions the ladder is helping you make.")
                .font(InkFont.display(11.5, .light)).foregroundStyle(Ink.dim).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            Text("A mid-or-better limit across the last \(stx.n) cycles would have recovered $\(grp(stx.recover)) of the $\(grp(stx.paid)).")
                .font(InkFont.display(11.5, .light)).foregroundStyle(PG_UP).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 9)
        }
        .padding(16)
        .overlay(alignment: .leading) { Rectangle().fill(Ink.text).frame(width: 2) }
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
    }

    private var twoStats: some View {
        HStack(spacing: 1) {
            statCell("Hit rate", "\(Int((stx.hitRate * 100).rounded()))%", PG_UP,
                     "±\(Int((plannerCI(stx.hitRate, stx.n) * 100).rounded())) pts · n=\(stx.n)")
            statCell("Assignment rate", "\(Int((stx.assignRate * 100).rounded()))%", Ink.text,
                     "±\(Int((plannerCI(stx.assignRate, stx.n) * 100).rounded())) pts · n=\(stx.n)")
        }
        .background(Ink.hair).clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
    }
    private func statCell(_ k: String, _ v: String, _ hue: Color, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            M(k, 8.5, 0.14)
            N(v, 24, hue).padding(.top, 9)
            M(sub, 7.5, 0.1).padding(.top, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 15, trailing: 14)).background(Ink.canvas)
    }

    private var bucketsView: some View {
        VStack(spacing: 0) {
            ForEach(stx.buckets) { bkt in
                HStack(spacing: 9) {
                    M(bkt.label, 8, 0.1).frame(width: 54, alignment: .leading)
                    if bkt.ok {
                        VStack(alignment: .leading, spacing: 3) {
                            GeometryReader { g in Capsule().fill(Ink.dim).frame(width: bkt.pred * g.size.width, height: 4) }.frame(height: 4)
                            GeometryReader { g in Capsule().fill(Ink.text).frame(width: bkt.act * g.size.width, height: 4) }.frame(height: 4)
                        }.frame(maxWidth: .infinity)
                        N("\(Int((bkt.pred * 100).rounded())) / \(Int((bkt.act * 100).rounded()))", 10.5).frame(width: 44, alignment: .trailing)
                    } else {
                        M("· · ·", 9, 0.3).frame(maxWidth: .infinity, alignment: .leading)
                        M("too few", 7.5, 0.1).frame(width: 44, alignment: .trailing)
                    }
                    M("n\(bkt.n)", 7.5, 0.08).frame(width: 22, alignment: .trailing)
                }
                .padding(.vertical, 7).opacity(bkt.ok ? 1 : 0.4)
            }
            HStack(spacing: 7) {
                Capsule().fill(Ink.dim).frame(width: 14, height: 4); M("predicted", 7.5, 0.12)
                Capsule().fill(Ink.text).frame(width: 14, height: 4).padding(.leading, 8); M("actual", 7.5, 0.12)
                Spacer(minLength: 0)
            }
            .padding(.top, 10).overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1).padding(.top, 4) }
        }
        .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
    }

    private var logView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                M("date", 7.5, 0.14).frame(width: 42, alignment: .leading)
                M("strike", 7.5, 0.14).frame(maxWidth: .infinity, alignment: .leading)
                M("mid → fill", 7.5, 0.14).frame(maxWidth: .infinity, alignment: .leading)
                M("miss", 7.5, 0.14).frame(width: 32, alignment: .trailing)
                M("outcome", 7.5, 0.14).frame(width: 50, alignment: .trailing)
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1) }
            ForEach(log.prefix(8)) { c in logRow(c) }
        }
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(Ink.hair, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard))
    }
    private func logRow(_ c: PlannerCycle) -> some View {
        let d = Date(timeIntervalSince1970: c.ts / 1000)
        let cal = Calendar(identifier: .gregorian)
        let day = cal.component(.day, from: d), mon = PL_MONTHS[cal.component(.month, from: d) - 1]
        return HStack(spacing: 6) {
            M("\(day) \(mon)", 8, 0.08).frame(width: 42, alignment: .leading)
            (N(nvStrikeStr(c.strike), 11) + M(" \(Int(c.ct))ct", 7.5, 0.08)).frame(maxWidth: .infinity, alignment: .leading)
            N(c.settled ? "\(fmt2(c.mid)) → \(fmt2(c.fill))" : "\(fmt2(c.mid)) → —", 11, Ink.dim).frame(maxWidth: .infinity, alignment: .leading)
            N(c.settled ? "−\(Int(((c.mid - c.fill) * 100).rounded()))¢" : "—", 11, PG_DOWN).frame(width: 32, alignment: .trailing)
            M(c.settled ? (c.assigned ? "assigned" : "expired") : "pending", 8, 0.1,
              c.settled ? (c.assigned ? PG_DOWN : Ink.text) : Ink.dim).frame(width: 50, alignment: .trailing)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .overlay(alignment: .top) { if c.id != log.first?.id { Rectangle().fill(Ink.hair).frame(height: 1) } }
    }
}

/// An InkRoll that returns a Text (for concatenation with a unit like ¢).
private func InkRollText(_ s: String, _ size: CGFloat, _ color: Color) -> Text {
    Text(s).font(InkFont.mono(size, .light)).foregroundStyle(color)
}

// MARK: - 05 · Commit bar (sticky)

struct CommitBarView: View {
    @Bindable var planner: PlannerStore
    let s: PlannerState

    private var b: PBook { s.book }
    private var g: PGate { s.gate }
    private var ct: Double { b.capacity }
    private var row: PRung? { s.selRung }
    private var wallRow: PRung? { s.wallRung }
    private var expiry: PExpiry? { s.expiries.first { $0.iso == s.selExpiry } ?? s.expiries.first }
    private var wall: Double { b.wall ?? 0 }
    private var histAssign: Double { planner.log.calStats.assignRate }

    var body: some View {
        guard let row, let e = expiry else { return AnyView(EmptyView()) }
        let extra = (row.prem - (wallRow?.prem ?? row.prem)) * 100 * ct
        let covers = b.shares * g.spot > 0 ? extra / (b.shares * g.spot) : 0
        let surrendered = (wall - row.strike) * 100 * ct
        let credit = row.prem * 100 * ct
        let bleedDays = b.longTheta > 0 ? credit / b.longTheta : 0
        let mult = histAssign > 0 ? row.assign / histAssign : 0

        let cells: [CommitCellData] = [
            .init("covers bleed", "\(fmt1(bleedDays)) days", sub: "$\(grp(b.longTheta)) / day", hue: bleedDays >= 1 ? PG_UP : PG_DOWN),
            .init("assign", "\(Int((row.assign * 100).rounded()))%"),
            .init("edge", pgSigned(row.edge, 0), hue: row.edge < 0 ? PG_DOWN : PG_UP),
            .init("net Δ · \(Int((row.pctLong * 100).rounded()))% long", signedInt(row.netDeltaAfter), hue: row.netDeltaAfter < 0 ? PG_DOWN : Ink.text),
            .init("extra vs \(nvStrikeStr(wall))", pgMoney(extra), hue: extra > 0 ? PG_UP : Ink.dim),
            .init("extra covers", "\(fmt2(covers * 100))%", sub: "of position"),
            .init("upside at +15%", surrendered > 0 ? "−$\(grp(surrendered))" : "—", hue: surrendered > 0 ? PG_DOWN : Ink.dim),
            .init("vs your rate", "\(Int((row.assign * 100).rounded()))% vs \(Int((histAssign * 100).rounded()))%", sub: "\(fmt1(mult))x your usual", subHue: mult > 1.5 ? PG_DOWN : Ink.dim),
            .init("lookback", planner.settings.edgeLookback.uppercased(), sub: "edge \(span(row.edgeHi, row.edgeLo))"),
        ]

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        N("\(e.label) · \(nvStrikeStr(row.strike)) C · \(Int(ct)) ct", 14)
                        M(row.advCost > 0 ? "\(Int(row.affected)) ct sit below your $\(nvStrikeStr(wall)) long calls" : "clear of the $\(nvStrikeStr(wall)) long-call wall", 7.5, 0.12)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 5) {
                        InkRoll(text: pgUsd(credit), font: InkFont.mono(22, .light), color: PG_UP)
                        M("credit at mid", 7.5, 0.12)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 10) {
                    ForEach(cells) { commitCell($0) }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1).padding(.top, -6) }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 30, trailing: 16))
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
        )
    }

    private func commitCell(_ c: CommitCellData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            M(c.k, 7.5, 0.12)
            N(c.v, 12, c.hue)
            if let sub = c.sub { M(sub, 8, 0.02, c.subHue, upper: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CommitCellData: Identifiable {
    let k: String; let v: String; var sub: String? = nil; var hue: Color = Ink.text; var subHue: Color = Ink.dim
    var id: String { k }
    init(_ k: String, _ v: String, sub: String? = nil, hue: Color = Ink.text, subHue: Color = Ink.dim) {
        self.k = k; self.v = v; self.sub = sub; self.hue = hue; self.subHue = subHue
    }
}

// MARK: - Shared section helpers

private func method(_ text: String) -> some View {
    Text(text).font(InkFont.display(11.5, .light)).foregroundStyle(Ink.dim).lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true).padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
}
private func caveat(_ text: String) -> some View {
    Text(text).font(InkFont.display(12, .light)).foregroundStyle(Ink.dim).lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 11).padding(.top, 12)
        .overlay(alignment: .leading) { Rectangle().fill(Ink.dim).frame(width: 2) }
        .frame(maxWidth: .infinity, alignment: .leading)
}
