//
//  PlannerThesis.swift
//  Sunny
//
//  Block 14c (handoff 27) · the Thesis page: why next week's call strike
//  sits where it does. One glass card: the strategy's premise, five
//  numbered sections in the order that strategy cares about, then the
//  receipt and the strike in a lighter pane at the end. Page 0 of the
//  Thesis and Planner screen; the Planner is one swipe left.
//
//  NKE's steps are the TESTED NKE rule's (docs/STRATEGIES.md): 0.6 SD,
//  +0.2 a step wider, "closer" a step in. Every other name follows the
//  Planner's own 0.6 SD rule (Nik, 19 Oct 2026: "Thesis for each page the
//  .6 planner for now"). Either way the strike is the one on the
//  Suggestions chip and in Position after the plan.
//

import SwiftUI

// MARK: - The words

struct Thesis {
    struct Line { let label: String; let value: String; let bold: Bool; var color: Color = S.ink }
    struct Fact { var t: String; var hl: String = ""; var hc: Color = S.muted; var t2: String = "" }
    struct Row: Identifiable {
        let id: String
        let name: String
        let read: String
        let readColor: Color
        let nameColor: Color
        let step: String
        let stepColor: Color
        let facts: [Fact]
    }
    struct Group: Identifiable { let id: String; let title: String; let rows: [Row] }

    let lines: [Line]
    let strike: String
    let detail: String
    /// In the strategy's order (Strategy.order), Portfolio delta last; numbered on screen.
    let groups: [Group]

    init(_ r: ReadRule, _ p: PlanPkg, afterP: Double, strategy: String?) {
        let spot = r.spot, px = Self.usd(spot)

        // The receipt: the server's lines when it writes them (the CALL RULE, 20 Oct 2026: weekly
        // calls at the money, the quarterly 1.5 SD call, delta at +1.5 SD); else baseline, steps, pick.
        if let rl = r.lines {
            lines = rl.map { Line(label: $0.label, value: $0.value, bold: false, color: $0.tone == "red" ? S.red : S.ink) }
        } else {
            var ls = [Line(label: "Baseline", value: "\(F.trim(r.baseline ?? 0.6)) SD", bold: false)]
            ls += r.steps.map { let (v, c) = Self.step($0.step); return Line(label: $0.label, value: v, bold: false, color: c) }
            ls.append(Line(label: "Pick", value: r.pick ?? r.pickSd.map { "\(F.trim($0)) SD" } ?? "", bold: true))
            lines = ls
        }
        strike = r.strike.map(Self.usd) ?? "None"
        let out = r.lines != nil ? r.calls : Int((Double(r.calls) * (1 - (r.atmShare ?? 0))).rounded())
        detail = r.strike.map { k in
            "\(String(format: "%.1f", abs((k / spot - 1) * 100)))% \(k >= spot ? "above" : "below") \(px) · \(out) of \(r.of) calls"
        } ?? "No calls this week"

        // The five sections.
        let R = r.reads, T = R.thesis, I = R.inputs
        let moved = Dictionary(grouping: r.steps) { $0.read == "breakout" ? "history" : $0.read }
        func row(_ key: String, _ name: String, _ read: ReadRule.Read?, word: String? = nil, solo: Bool = false, _ facts: [Fact]) -> Row {
            let steps = moved[key] ?? []
            let w = word ?? Self.cap(read?.read ?? "none")
            let tone: Color = {
                guard !steps.isEmpty else { return S.ink }
                let x = read?.read ?? ""
                return x == "bullish" ? S.green : x == "bearish" ? S.red : S.orangeDeep
            }()
            let shown = steps.map { Self.step($0.step) }
            return Row(id: key, name: solo ? "" : name, read: w, readColor: tone,
                       nameColor: steps.isEmpty ? S.muted : S.ink,
                       step: shown.map(\.0).joined(separator: " "),
                       stepColor: shown.contains { $0.1 == S.red } ? S.red : S.ink, facts: facts)
        }

        // 1 · Fundamentals
        var fund: [Fact] = []
        if let f = R.fundamentals {
            let parts = [f.analyst.map { "Analyst target \(Self.usd($0))" }, f.model.map { "model target \(Self.usd($0))" }].compactMap { $0 }
            if !parts.isEmpty { fund.append(Fact(t: parts.joined(separator: " · "))) }
            if let v = f.value {
                let d = (v / spot - 1) * 100
                fund.append(Fact(t: "Fair value \(Self.usd(v)), ", hl: "\(Int(abs(d).rounded()))%", hc: d >= 0 ? S.green : S.red,
                                 t2: " \(d >= 0 ? "above" : "below") \(px)"))
            }
        }
        // 2 · Price: technicals, history, momentum
        var tech: [Fact] = []
        if let T {
            let smas = [(10, T.sma10), (50, T.sma50), (100, T.sma100), (200, T.sma200)]
                .compactMap { d, v in v.map { (d, $0) } }
            let above = smas.filter { spot > $0.1 }, below = smas.filter { spot <= $0.1 }
            for (word, set) in [("Above", above), ("Below", below)] where !set.isEmpty {
                let items = set.enumerated().map { i, x in (i == 0 ? "the " : "") + "\(x.0)-day \(Self.usd(x.1))" }
                tech.append(Fact(t: "\(word) " + Self.and(items)))
            }
        }
        var hist: [Fact] = []
        if let c5 = T?.close5 { hist.append(Fact(t: "\(Self.usd(c5)) to \(px) in 5 days")) }
        if let lo = T?.mLo, let hi = T?.mHi, hi > lo {
            let at = (spot - lo) / (hi - lo)
            let where_ = at >= 2.0 / 3 ? "Top" : at <= 1.0 / 3 ? "Bottom" : "Middle"
            hist.append(Fact(t: "\(where_) of the month's range, \(Self.usd(lo)) to \(Self.usd(hi))"))
        }
        if moved["history"]?.contains(where: { $0.read == "breakout" }) == true, let b = R.breakout {
            hist.append(Fact(t: Self.cap(b.fact)))
        }
        var mom: [Fact] = []
        if let s2 = T?.sma200 {
            let falling = (T?.sma200Ago).map { s2 < $0 } ?? false
            mom.append(Fact(t: "\(spot < s2 ? "Under" : "Over") a \(falling ? "falling" : "rising") 200-day line, \(Self.usd(s2))"))
        }
        if let y = T?.chg252 {
            mom.append(Fact(t: y < 0 ? "Down " : "Up ", hl: "\(Int(abs(y).rounded()))%", hc: y < 0 ? S.red : S.green, t2: " over the year"))
        }
        // 3 · IV
        var iv: [Fact] = []
        let usual = T?.ivUsual.map { "Usual \(Int(($0 * 100).rounded()))%" }
        let real = I?.hv20Ex.map { "realised \(Int(($0 * 100).rounded()))% over the month" }
        let ivLine = [usual, real].compactMap { $0 }.joined(separator: " · ")
        if !ivLine.isEmpty { iv.append(Fact(t: ivLine)) }
        if let x = I?.rich { iv.append(Fact(t: "Selling at \(String(format: "%.1f", x))x what it actually moves")) }
        let ivWord = I?.iv.map { "\(Int(($0 * 100).rounded()))% now" } ?? Self.cap(R.iv?.read ?? "none")
        // 4 · Events
        var ev: [Fact] = []
        let clear = (R.events?.read ?? "clear") == "clear"
        ev.append(Fact(t: clear ? "Nothing before the \(F.day(p.plannedFor)) expiry"
                                : Self.cap(R.events?.fact.components(separatedBy: ". ").first ?? "")))
        var next: [(String, String)] = []
        if let e = I?.nextEarnings { next.append((e, "earnings \(F.day(e))")) }
        if let d = I?.exDiv { next.append((d, "ex-dividend \(I?.exDivEstimated == true ? "about " : "")\(F.day(d))")) }
        if !next.isEmpty { ev.append(Fact(t: "Next · " + next.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: ", "))) }
        // 5 · Portfolio delta: the Planner's Delta card numbers
        let band = p.band(afterP)
        let dl = [Fact(t: "\(Int(abs(p.nowPct).rounded()))% left now, \(Int(abs(afterP).rounded()))% after the plan"),
                  Fact(t: "Target \(Int(20 + p.e)) to \(Int(30 + p.e))% of \(Int(p.base).formatted()) LEAP shares")]

        let all = [
            Group(id: "f", title: "Fundamentals", rows: [row("fundamentals", "Fundamentals", R.fundamentals, solo: true, fund)]),
            Group(id: "p", title: "Price", rows: [
                row("technicals", "Technicals", R.technicals, tech),
                row("history", "History", R.history, hist),
                row("momentum", "Momentum", R.momentum, mom),
            ]),
            Group(id: "i", title: "IV", rows: [row("iv", "IV", R.iv, word: ivWord, solo: true, iv)]),
            Group(id: "e", title: "Events", rows: [row("events", "Events", R.events, word: clear ? "None found" : nil, solo: true, ev)]),
            Group(id: "d", title: "Portfolio delta", rows: [row("delta", "Portfolio delta", nil, word: band.rawValue, solo: true, dl)]),
        ]
        groups = Strategy.order(strategy).compactMap { id in all.first { $0.id == id } }
    }

    /// A step on the right and in the receipt: "+0.2" as it is; a step in
    /// ("closer", or a negative) in S.red with no minus sign (14c, Steps).
    static func step(_ s: String) -> (String, Color) {
        if s == "closer" { return ("Closer", S.red) }
        if s.hasPrefix("-") || s.hasPrefix("\u{2212}") { return (String(s.dropFirst()), S.red) }
        return (s, S.ink)
    }

    /// $38.50 · $37 · $1,204.50
    static func usd(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.005 { return F.money(v) }
        // Rounded as the backend's facts are (toFixed), so $42.05 matches.
        return v < 1000 ? "$" + String(format: "%.2f", abs(v)) : F.money(v, cents: true)
    }
    static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
    /// "a", "a and b", "a, b and c"
    static func and(_ xs: [String]) -> String {
        xs.count < 2 ? (xs.first ?? "") : xs.dropLast().joined(separator: ", ") + " and " + xs.last!
    }
}

// MARK: - The Thesis page

struct PlannerThesisView: View {
    let ticker: String
    let strategy: String?
    /// nil: no thesis for this name yet (no reads, or no chain).
    let th: Thesis?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let name = Strategy.name(strategy), let premise = Strategy.premise(strategy) {
                (Text(name).font(SType(size: 15, weight: 700, line: 20, tracking: 0).font()).foregroundStyle(S.ink)
                 + Text(" · " + premise))
                    .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let th {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(th.groups.enumerated()), id: \.element.id) { i, g in group(g, n: i + 1) }
                }
                receipt(th)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No thesis for \(ticker) yet").sType(SType(size: 17, weight: 600, line: 22, tracking: 0), tabular: false)
                    Text("The weekly calls sell at the money. The reads for this page are not in yet.")
                        .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    /// The lighter pane at the end: white 55%, dark white 6%, 20 radius.
    private func receipt(_ th: Thesis) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(th.lines.enumerated()), id: \.offset) { _, l in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(l.label).sType(SType(size: 15, weight: l.bold ? 700 : 500, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(l.bold ? S.ink : S.muted)
                    Spacer(minLength: 0)
                    Text(l.value).sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                        .foregroundStyle(l.color)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(S.pRule).frame(height: 1) }
            }
            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Strike").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false)
                    Spacer(minLength: 0)
                    Text(th.strike).sType(.largeNumber)
                }
                Text(th.detail).sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                    .foregroundStyle(S.muted)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.top, 14)
        }
        .padding(.top, 6).padding(.horizontal, 20).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(scheme == .dark ? 0.06 : 0.55)))
        .accessibilityElement(children: .combine)
    }

    /// "1 EVENTS", then one read a line with its facts; padding 16 0 4 under a rule.
    private func group(_ g: Thesis.Group, n: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n)").sType(SType(size: 13, weight: 700, line: 16, tracking: 0))
                Text(g.title.uppercased()).sType(SType(size: 13, weight: 700, line: 16, tracking: 0.04), tabular: false)
            }
            .foregroundStyle(S.muted)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(g.rows) { r in row(r) }
        }
        .padding(.top, 16).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
    }

    private func row(_ r: Thesis.Row) -> some View {
        let f17 = { (w: CGFloat) in SType(size: 17, weight: w, line: 22, tracking: 0).font() }
        let line = r.name.isEmpty
            ? Text(r.read).font(f17(700)).foregroundStyle(r.readColor)
            : Text(r.name + " ").font(f17(500)).foregroundStyle(r.nameColor) + Text(r.read).font(f17(700)).foregroundStyle(r.readColor)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                line.sType(SType(size: 17, weight: 500, line: 22, tracking: 0), tabular: false)
                ForEach(Array(r.facts.enumerated()), id: \.offset) { _, f in
                    let w = SType(size: 13, weight: 600, line: 18, tracking: 0)
                    (Text(f.t) + Text(f.hl).font(w.font(tabular: true)).foregroundStyle(f.hc) + Text(f.t2))
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                        .foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if !r.step.isEmpty {
                Text(r.step).sType(SType(size: 17, weight: 700, line: 22, tracking: 0))
                    .foregroundStyle(r.stepColor)
            }
        }
        .padding(.top, 8).padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
}
