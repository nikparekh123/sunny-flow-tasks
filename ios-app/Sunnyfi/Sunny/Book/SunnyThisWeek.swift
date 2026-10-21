//
//  SunnyThisWeek.swift
//  Sunny
//
//  Block 12b (handoffs 28 and 29, 20 Oct 2026) · This week: what to roll, buy and
//  sell by Friday, one row per task, from the CALL RULE (Nik: "our live rule, ignore
//  the design rule"; "include everything", so next Friday's sales are rows too).
//  Short | Long splits the list (what you sold, what you buy), five most urgent
//  on each side, the rest behind Show more.
//  Checking a row is you saying it is done; the app places no orders. Checked,
//  it strikes through, waits 1.2 s (tap again to undo), then folds away and does
//  not come back that day. The last one folds the whole card.
//

import SwiftUI

struct SunnyThisWeek: View {
    let home: HomePayload
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme
    /// Rows ticked in the last 1.2 s: still on screen, struck through.
    @State private var pending: Set<String> = []

    /// Today's rows: every task not checked today.
    static func open(_ home: HomePayload, checked: [String: String]) -> [WeekTask] {
        (home.thisWeek?.value ?? []).filter { checked[$0.id] != home.today }
    }
    /// Short is what you sold (rolls, calls and puts to sell); Long is what you buy.
    static func side(_ r: WeekTask) -> String { r.kind == "buy" ? "l" : "s" }

    var body: some View {
        let rows = Self.open(home, checked: router.checked)
        let left = rows.filter { !pending.contains($0.id) }.count
        let mine = rows.filter { Self.side($0) == router.weekSide }
        let shown = router.weekMore ? mine : Array(mine.prefix(5))
        let counts = ["s", "l"].map { s in rows.filter { Self.side($0) == s && !pending.contains($0.id) }.count }
        Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("To do").sType(.sectionTitle, tabular: false)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        Text("\(left) left · by Fri")
                            .sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
                            .foregroundStyle(S.muted)
                            .contentTransition(.numericText(value: Double(left)))
                    }
                    .padding(.bottom, 12)
                    WeekSideSwitch(side: router.weekSide, counts: counts) { s in
                        guard s != router.weekSide else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(reduce ? .easeOut(duration: 0.2) : S.standard(0.35)) { router.weekSide = s }
                    }
                    .padding(.bottom, 14)
                    ForEach(shown) { r in
                        row(r)
                            .transition(.opacity.combined(with: .scale(scale: 1, anchor: .top)))
                    }
                    if mine.isEmpty {
                        Text("Nothing \(router.weekSide == "s" ? "short" : "long") to do this week")
                            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted)
                            .padding(.top, 14).padding(.bottom, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
                    }
                    if mine.count > 5 { more(mine.count - 5) }
                }
                .foregroundStyle(S.ink)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
                .sunnyGlow()
                .transition(.opacity)
            }
        }
        .animation(reduce ? .easeOut(duration: 0.2) : S.standard(0.35), value: shown.map(\.id))
        // From a card's rebalance row: that name's side, Show more if its task is past the fifth.
        .onChange(of: router.nxRing) { _, t in
            guard let t, let r = rows.first(where: { $0.t == t }) else { return }
            let s = Self.side(r), i = rows.filter { Self.side($0) == s }.firstIndex { $0.t == t } ?? 0
            withAnimation(reduce ? nil : S.standard(0.35)) {
                router.weekSide = s
                if i >= 5 { router.weekMore = true }
            }
        }
    }

    /// "Show 11 more" or "Show less": 48 tall, centred, the chevron turns.
    private func more(_ n: Int) -> some View {
        Button {
            withAnimation(reduce ? nil : S.standard(0.35)) { router.weekMore.toggle() }
        } label: {
            HStack(spacing: 8) {
                Text(router.weekMore ? "Show less" : "Show \(n) more")
                    .sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                    .contentTransition(.numericText(value: Double(n)))
                Path { q in q.move(to: CGPoint(x: 1.5, y: 1.5)); q.addLine(to: CGPoint(x: 6, y: 6)); q.addLine(to: CGPoint(x: 10.5, y: 1.5)) }
                    .stroke(S.muted, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 12, height: 8)
                    .rotationEffect(.degrees(router.weekMore ? 180 : 0))
                    .animation(reduce ? nil : S.standard(0.3), value: router.weekMore)
            }
            .foregroundStyle(S.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(POpacity())
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
    }

    // MARK: A row

    private func row(_ r: WeekTask) -> some View {
        let done = pending.contains(r.id), lit = router.nxRing == r.t
        return HStack(alignment: .center, spacing: 12) {
            Button { toggle(r) } label: {
                // The design's checkbox: a 1.5 pt ring (60,60,67 at 30%; dark 235,235,245 at 36%), filled
                // ink with a 12 x 10 tick once checked.
                ZStack {
                    Circle().strokeBorder(scheme == .dark ? Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.36)
                                                          : Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3), lineWidth: 1.5)
                        .opacity(done ? 0 : 1)
                    Circle().fill(S.ink).opacity(done ? 1 : 0)
                    Path { q in q.move(to: CGPoint(x: 1.5, y: 5.2)); q.addLine(to: CGPoint(x: 4.5, y: 8)); q.addLine(to: CGPoint(x: 10.5, y: 1.8)) }
                        .stroke(S.paper, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 10)
                        .opacity(done ? 1 : 0)
                }
                .frame(width: 22, height: 22)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.2), value: done)
            }
            .buttonStyle(.plain)
            .padding(.leading, -11)
            .accessibilityLabel(done ? "Done. Tap to undo" : "Mark done")

            Button { router.openCard(r.t, face: r.face) } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.t).sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false)
                            .foregroundStyle(lit ? S.orangeDeep : S.ink)
                        // Two lines at most (Nik, 20 Oct 2026): the ticker, then the action on one line.
                        Text(r.action).foregroundStyle(lit ? S.orangeDeep : S.ink)
                            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                            .strikethrough(done)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        (Text(PF.usd(r.cost)).foregroundStyle(r.credit ? S.green : S.ink)
                         + Text(r.credit ? " credit" : "").font(SType(size: 13, weight: 500, line: 20, tracking: 0).font())
                            .foregroundStyle(S.green))
                            .sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                        Text(Self.deltaWords(r.delta))
                            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                            .foregroundStyle(r.delta < 0 ? S.red : S.muted)
                    }
                    .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(r.t), \(r.action), \(PF.usd(r.cost))\(r.credit ? " credit" : ""), \(Self.deltaWords(r.delta))")
            .accessibilityHint("Opens \(r.t) in Positions")
        }
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .opacity(done ? 0.45 : 1)
        .animation(.easeOut(duration: 0.2), value: done)
        .animation(.easeInOut(duration: 0.4), value: lit)
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
    }

    /// "+$7.9K delta" when it adds (the design's one plus sign); "$36K delta" in red, no sign, when it
    /// takes some away (handoff 29: selling calls, buying puts).
    static func deltaWords(_ v: Double) -> String {
        v >= 0 ? "+\(PF.usd(v)) delta" : "\(PF.usd(v)) delta"
    }

    /// Tick, wait 1.2 s, then leave for the day; a second tap inside the beat undoes it.
    private func toggle(_ r: WeekTask) {
        if pending.contains(r.id) { pending.remove(r.id); return }
        UISelectionFeedbackGenerator().selectionChanged()
        pending.insert(r.id)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard pending.contains(r.id) else { return }
            withAnimation(reduce ? .easeOut(duration: 0.2) : S.standard(0.35)) {
                router.check(r.id, day: home.today)
                pending.remove(r.id)
            }
        }
    }
}

/// Short | Long (handoff 29): the system segmented control, so it is iOS 26 Liquid Glass natively
/// (Nik, 20 Oct 2026), each side with its count.
private struct WeekSideSwitch: View {
    let side: String
    let counts: [Int]
    let pick: (String) -> Void

    var body: some View {
        Picker("Short or long", selection: Binding(get: { side }, set: { pick($0) })) {
            Text("Short  \(counts[safe: 0] ?? 0)").tag("s")
            Text("Long  \(counts[safe: 1] ?? 0)").tag("l")
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }
}

/// Press dims to 60%.
private struct POpacity: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
