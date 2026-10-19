//
//  PlannerThesis.swift
//  Sunny
//
//  Block 14c (handoff 26) · Our thesis: why the Planner picked its call
//  strike. The answer first in one glass card (the baseline, each step, the
//  pick and the strike), then the facts in five numbered sections. Opens
//  from a row at the bottom of Suggestions; Back returns to the Planner.
//
//  The steps are the TESTED NKE rule's (docs/STRATEGIES.md, NKE weekly rule):
//  0.6 SD, +0.2 SD a step wider, "closer" a step in (Nik, 19 Oct 2026), not
//  the design's +0.1 a read. The strike is sunny-home's read_rule strike, the
//  same one on the Suggestions chip and in Position after the plan.
//

import SwiftUI

// MARK: - The words

struct Thesis {
    struct Line { let label: String; let value: String; let bold: Bool }
    struct Fact { var t: String; var hl: String = ""; var hc: Color = S.muted; var t2: String = "" }
    struct Row: Identifiable {
        let id: String
        let name: String
        let read: String
        let readColor: Color
        let nameColor: Color
        let step: String
        let facts: [Fact]
    }
    struct Group: Identifiable { let id: String; let n: Int; let title: String; let rows: [Row] }

    let ticker: String
    let price: String
    let lines: [Line]
    let strike: String
    let detail: String
    let groups: [Group]
    let entry: String

    init(_ r: ReadRule, _ p: PlanPkg, afterP: Double) {
        let spot = r.spot, px = Self.usd(spot)
        ticker = p.t
        price = String(format: "%.2f", spot)

        // The receipt: baseline, steps, pick; then the strike.
        var ls = [Line(label: "Baseline", value: "\(F.trim(r.baseline ?? 0.6)) SD", bold: false)]
        ls += r.steps.map { Line(label: $0.label, value: $0.step, bold: false) }
        ls.append(Line(label: "Pick", value: r.pick ?? r.pickSd.map { "\(F.trim($0)) SD" } ?? "", bold: true))
        lines = ls
        strike = r.strike.map(Self.usd) ?? "None"
        let out = Int((Double(r.calls) * (1 - (r.atmShare ?? 0))).rounded())
        detail = r.strike.map { k in
            "\(String(format: "%.1f", abs((k / spot - 1) * 100)))% \(k >= spot ? "above" : "below") \(px) · \(out) of \(r.of) calls"
        } ?? "No calls this week"

        // The row line under Suggestions.
        let plus = r.steps.filter { $0.step.hasPrefix("+") }
        let sum = plus.compactMap { Double($0.step.dropFirst()) }.reduce(0, +)
        var why = r.strike.map { "Why \(Self.usd($0)) · " } ?? "Why no calls · "
        if r.steps.isEmpty { why += "the \(F.trim(r.baseline ?? 0.6)) SD baseline" }
        else {
            why += "\(F.trim(r.baseline ?? 0.6)) SD"
            if !plus.isEmpty { why += " plus \(F.trim(sum)) from " + Self.and(plus.map(\.read)) }
            let other = r.steps.filter { !$0.step.hasPrefix("+") }
            if !other.isEmpty { why += (plus.isEmpty ? ", " : " · ") + other.map { "\($0.step) on \($0.read)" }.joined(separator: ", ") }
        }
        entry = why

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
            return Row(id: key, name: solo ? "" : name, read: w, readColor: tone,
                       nameColor: steps.isEmpty ? S.muted : S.ink,
                       step: steps.map(\.step).joined(separator: " "), facts: facts)
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

        groups = [
            Group(id: "f", n: 1, title: "Fundamentals", rows: [row("fundamentals", "Fundamentals", R.fundamentals, solo: true, fund)]),
            Group(id: "p", n: 2, title: "Price", rows: [
                row("technicals", "Technicals", R.technicals, tech),
                row("history", "History", R.history, hist),
                row("momentum", "Momentum", R.momentum, mom),
            ]),
            Group(id: "i", n: 3, title: "IV", rows: [row("iv", "IV", R.iv, word: ivWord, solo: true, iv)]),
            Group(id: "e", n: 4, title: "Events", rows: [row("events", "Events", R.events, word: clear ? "None found" : nil, solo: true, ev)]),
            Group(id: "d", n: 5, title: "Portfolio delta", rows: [row("delta", "Portfolio delta", nil, word: band.rawValue, solo: true, dl)]),
        ]
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

// MARK: - The entry row (bottom of Suggestions)

struct ThesisEntry: View {
    let line: String
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Our thesis").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.ink)
                    Text(line).sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
                        .foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Path { q in q.move(to: CGPoint(x: 1.5, y: 1.5)); q.addLine(to: CGPoint(x: 6.5, y: 7)); q.addLine(to: CGPoint(x: 1.5, y: 12.5)) }
                    .stroke(S.muted, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 8, height: 14)
            }
            .padding(.top, 8)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(ThesisPress())
        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
        .padding(.bottom, -8)
        .accessibilityLabel("Our thesis. \(line)")
    }
}

/// Press dims to 60% (block 14c, Entry).
private struct ThesisPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - The thesis view

struct PlannerThesisView: View {
    let th: Thesis
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                (Text(th.ticker).font(SType(size: 20, weight: 700, line: 24, tracking: 0).font())
                 + Text(" " + th.price).font(SType(size: 20, weight: 500, line: 24, tracking: 0).font(tabular: true)).foregroundStyle(S.muted))
                    .sType(SType(size: 20, weight: 700, line: 24, tracking: 0))
                    .lineLimit(1)
                Text("Calls to sell for next week · by Fri").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted)
            }
            .modifier(ThesisRise(on: shown, i: 0))
            receipt.modifier(ThesisRise(on: shown, i: 0))
            Text("OUR THESIS").sType(SType(size: 13, weight: 700, line: 16, tracking: 0.04), tabular: false)
                .foregroundStyle(S.muted)
                .padding(.top, 8)
                .modifier(ThesisRise(on: shown, i: 1))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                let idx = Self.indexes(th.groups)
                ForEach(Array(th.groups.enumerated()), id: \.element.id) { gi, g in
                    group(g, at: idx[gi])
                }
            }
            .padding(.top, -8)
        }
        .foregroundStyle(S.ink)
        .task { await enter() }
    }

    /// The design's stagger: name line and receipt 0, label 1, then each
    /// section takes the index of its first row and every row the next.
    static func indexes(_ gs: [Thesis.Group]) -> [(group: Int, rows: [Int])] {
        var i = 2
        return gs.map { g in
            let gIndex = i
            let rows = g.rows.map { _ -> Int in defer { i += 1 }; return i }
            return (gIndex, rows)
        }
    }

    private func enter() async {
        var t = Transaction(); t.disablesAnimations = true
        if reduce { withTransaction(t) { shown = true }; return }
        withTransaction(t) { shown = false }
        try? await Task.sleep(for: .milliseconds(32))
        shown = true
    }

    private var receipt: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(th.lines.enumerated()), id: \.offset) { _, l in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(l.label).sType(SType(size: 15, weight: l.bold ? 700 : 500, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(l.bold ? S.ink : S.muted)
                    Spacer(minLength: 0)
                    Text(l.value).sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(S.pRule).frame(height: 1) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Strike").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false)
                Spacer(minLength: 0)
                Text(th.strike).sType(.largeNumber)
            }
            .padding(.top, 14)
            Text(th.detail).sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                .foregroundStyle(S.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .padding(.top, 6)
        }
        .padding(.top, 6).padding(.horizontal, 20).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func group(_ g: Thesis.Group, at ix: (group: Int, rows: [Int])) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(g.n)").sType(SType(size: 15, weight: 600, line: 22, tracking: 0))
                .foregroundStyle(S.muted)
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(g.title.uppercased()).sType(SType(size: 13, weight: 700, line: 22, tracking: 0.04), tabular: false)
                    .foregroundStyle(S.muted)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(g.rows.enumerated()), id: \.element.id) { j, r in
                    row(r).modifier(ThesisRise(on: shown, i: ix.rows[j]))
                }
            }
        }
        .padding(.top, 14).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
        .modifier(ThesisRise(on: shown, i: ix.group))
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
            }
        }
        .padding(.top, 4).padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Rise 10 pt and fade in, 70 ms apart: opacity 0.4 s, move 0.5 s
/// (S.ease.standard). Reduce Motion: everything at once.
private struct ThesisRise: ViewModifier {
    let on: Bool
    let i: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        let d = Double(i) * S.stagger
        content
            .opacity(on ? 1 : 0)
            .animation(reduce || !on ? nil : .easeOut(duration: 0.4).delay(d), value: on)
            .offset(y: on || reduce ? 0 : 10)
            .animation(reduce || !on ? nil : S.standard(0.5).delay(d), value: on)
    }
}
