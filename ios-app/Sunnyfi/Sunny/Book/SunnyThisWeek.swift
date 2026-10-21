//
//  SunnyThisWeek.swift
//  Sunny
//
//  Block 12b (handoffs 28 and 29, 20 Oct 2026) · This week: what to roll, buy and
//  sell by Friday, one row per task, from the CALL RULE (Nik: "our live rule, ignore
//  the design rule"; "include everything", so next Friday's sales are rows too).
//  Tickers across the top (Nik, 21 Oct 2026, replacing To sell | To buy): pick one
//  to see its actions, each row the action only, and that name's total.
//  Checking a row is you saying it is done; the app places no orders. Checked,
//  it strikes through, waits 1.2 s (tap again to undo), then moves to Done today
//  at the bottom of its side, struck through, until the day ends (Nik, 21 Oct
//  2026). A fill that leaves more to do brings the follow-up row back up top.
//

import SwiftUI

struct SunnyThisWeek: View {
    let home: HomePayload
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme
    /// Rows ticked in the last 1.2 s: still on screen, struck through.
    @State private var pending: Set<String> = []

    /// Today's open rows: every task not ticked today at what is held now. A fill changes what is held,
    /// so a partial fill's "Buy 15 more" shows straight away (Nik, 21 Oct 2026).
    static func open(_ home: HomePayload, checked: [String: DoneTask]) -> [WeekTask] {
        (home.thisWeek?.value ?? []).filter { r in checked["\(r.id)@\(r.held ?? 0)"]?.day != home.today }
    }
    /// Ticked today, newest first.
    static func done(_ home: HomePayload, checked: [String: DoneTask]) -> [DoneTask] {
        checked.values.filter { $0.day == home.today }.sorted { $0.key < $1.key }
    }
    static func side(_ kind: String) -> String { kind == "buy" ? "l" : "s" }
    /// To sell: rolls (net a sale) and calls and puts to sell; To buy: calls to buy (Nik, 21 Oct 2026, was Short | Long).
    static func side(_ r: WeekTask) -> String { side(r.kind) }
    /// Tickers in the order the rows come (most urgent first), then any with only Done today rows.
    static func tickers(_ rows: [WeekTask], _ done: [DoneTask]) -> [String] {
        var names: [String] = []
        for r in rows where !names.contains(r.t) { names.append(r.t) }
        for d in done where !names.contains(d.t) { names.append(d.t) }
        return names
    }

    var body: some View {
        let rows = Self.open(home, checked: router.checked)
        let left = rows.filter { !pending.contains($0.id) }.count
        let doneAll = Self.done(home, checked: router.checked)
        let names = Self.tickers(rows, doneAll)
        let cur = names.contains(router.weekTicker ?? "") ? router.weekTicker! : (names.first ?? "")
        let mine = rows.filter { $0.t == cur }
        let doneMine = doneAll.filter { $0.t == cur }
        Group {
            if !names.isEmpty {
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
                    chips(names, cur: cur, rows: rows)
                        .padding(.bottom, 12)
                    ForEach(mine) { r in
                        row(r)
                            .transition(.opacity.combined(with: .scale(scale: 1, anchor: .top)))
                    }
                    if mine.isEmpty {
                        Text("Nothing left for \(cur) this week")
                            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted)
                            .padding(.top, 14).padding(.bottom, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
                    }
                    let open = mine.filter { !pending.contains($0.id) }
                    if !open.isEmpty { total(open) }
                    if !doneMine.isEmpty { doneGroup(doneMine) }
                }
                .foregroundStyle(S.ink)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
                .sunnyGlow()
                .transition(.opacity)
            }
        }
        .animation(reduce ? .easeOut(duration: 0.2) : S.standard(0.35), value: mine.map(\.id))
        .animation(reduce ? .easeOut(duration: 0.2) : S.standard(0.35), value: doneAll.map(\.key))
        // From a card's rebalance row: that name's chip.
        .onChange(of: router.nxRing) { _, t in
            guard let t, names.contains(t) else { return }
            withAnimation(reduce ? nil : S.standard(0.35)) { router.weekTicker = t }
        }
    }

    /// The tickers across the top, scrolling sideways: the picked one in ink, each with what is left.
    private func chips(_ names: [String], cur: String, rows: [WeekTask]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(names, id: \.self) { t in
                        let on = t == cur, n = rows.filter { $0.t == t && !pending.contains($0.id) }.count
                        Button {
                            guard !on else { return }
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(reduce ? .easeOut(duration: 0.2) : S.standard(0.35)) { router.weekTicker = t }
                        } label: {
                            HStack(spacing: 6) {
                                Text(t).sType(SType(size: 13, weight: 700, line: 13, tracking: 0), tabular: false)
                                Text(n > 0 ? "\(n)" : "done")
                                    .sType(SType(size: 13, weight: 500, line: 13, tracking: 0))
                                    .foregroundStyle(on ? S.chipOnInk.opacity(0.72) : S.muted)
                                    .contentTransition(.numericText(value: Double(n)))
                            }
                            .foregroundStyle(on ? S.chipOnInk : S.ink)
                            .padding(.horizontal, 12).frame(height: 32)
                            .background { if on { Capsule().fill(S.chipOn) } }
                            .glassEffect(on ? .identity : .regular.interactive(), in: .capsule)
                            .contentShape(Capsule().inset(by: -6))
                            .animation(.easeOut(duration: 0.2), value: on)
                        }
                        .buttonStyle(SPressStyle(scale: 0.96))
                        .accessibilityLabel("\(t), \(n > 0 ? "\(n) to do" : "done")")
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .id(t)
                    }
                }
                .padding(.vertical, 8)
            }
            // Inside the card's 20 pt padding, clipped at it: the chips never run past the card
            // (Nik, 21 Oct 2026). The 8 pt above and below keeps the chip shadows inside the clip.
            .scrollIndicators(.hidden)
            .padding(.vertical, -8)
            .onChange(of: cur) { _, t in withAnimation(reduce ? nil : S.standard(0.35)) { proxy.scrollTo(t, anchor: .center) } }
        }
    }

    /// The ticker's total, always the last line (Nik, 21 Oct 2026): every open row for that name,
    /// ticked rows out. Cash nets (a credit less what rolls cost); delta nets too.
    private func total(_ rows: [WeekTask]) -> some View {
        let cash = rows.reduce(0.0) { $0 + ($1.credit ? $1.cost : -$1.cost) }   // > 0: a credit
        let delta = rows.reduce(0.0) { $0 + $1.delta }
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false)
                Text("\(rows.count) to do").sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                    .foregroundStyle(S.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                (Text(PF.usd(cash)).foregroundStyle(cash > 0 ? S.green : S.ink)
                 + Text(cash > 0 ? " credit" : "").font(SType(size: 13, weight: 500, line: 20, tracking: 0).font())
                    .foregroundStyle(S.green))
                    .sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                    .contentTransition(.numericText(value: cash))
                Text(Self.deltaWords(delta))
                    .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                    .foregroundStyle(delta < 0 ? S.red : S.muted)
                    .contentTransition(.numericText(value: delta))
            }
            .lineLimit(1)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total, \(rows.count) to do, \(PF.usd(cash))\(cash > 0 ? " credit" : ""), \(Self.deltaWords(delta))")
    }

    /// Done today: the rows ticked today on this side, struck through, at the bottom. Tap the filled
    /// circle to undo; tap the row to open the card.
    private func doneGroup(_ items: [DoneTask]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Done today · \(items.count)")
                .sType(SType(size: 13, weight: 600, line: 16, tracking: 0))
                .foregroundStyle(S.muted)
                .padding(.top, 14).padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
                .accessibilityAddTraits(.isHeader)
            ForEach(items, id: \.key) { d in
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        withAnimation(reduce ? .easeOut(duration: 0.2) : S.standard(0.35)) { router.uncheck(d.key) }
                    } label: {
                        ZStack {
                            Circle().fill(S.ink)
                            Path { q in q.move(to: CGPoint(x: 1.5, y: 5.2)); q.addLine(to: CGPoint(x: 4.5, y: 8)); q.addLine(to: CGPoint(x: 10.5, y: 1.8)) }
                                .stroke(S.paper, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .frame(width: 12, height: 10)
                        }
                        .frame(width: 22, height: 22)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, -11)
                    .accessibilityLabel("Done: \(d.t), \(d.action). Tap to undo")
                    Button { router.openCard(d.t, face: d.face) } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Text(d.action).sType(SType(size: 15, weight: 500, line: 20, tracking: 0))
                                .strikethrough()
                                .lineLimit(1).minimumScaleFactor(0.75)
                            Spacer(minLength: 8)
                            (Text(PF.usd(d.cost)) + Text(d.credit ? " credit" : "").font(SType(size: 13, weight: 500, line: 20, tracking: 0).font()))
                                .sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                                .strikethrough()
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens \(d.t) in Positions")
                }
                .foregroundStyle(S.ink)
                .opacity(0.45)
                .frame(minHeight: 52)
                .transition(.opacity)
            }
        }
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
                    // The action only; the chip above names the ticker (Nik, 21 Oct 2026).
                    Text(r.action).foregroundStyle(lit ? S.orangeDeep : S.ink)
                        .sType(SType(size: 15, weight: 500, line: 20, tracking: 0))
                        .strikethrough(done)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)
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
                    .fixedSize()
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

    /// Tick, wait 1.2 s, then move to Done today; a second tap inside the beat undoes it.
    private func toggle(_ r: WeekTask) {
        if pending.contains(r.id) { pending.remove(r.id); return }
        UISelectionFeedbackGenerator().selectionChanged()
        pending.insert(r.id)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard pending.contains(r.id) else { return }
            withAnimation(reduce ? .easeOut(duration: 0.2) : S.standard(0.35)) {
                router.check(r, day: home.today)
                pending.remove(r.id)
            }
        }
    }
}

/// Press dims to 60%.
private struct POpacity: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
