//
//  SunnyThisWeek.swift
//  Sunny
//
//  Block 12b (handoff 28, 20 Oct 2026) · This week: what to roll, buy and sell
//  by Friday, one row per task, from the CALL RULE (Nik: "our live rule, ignore
//  the design rule"; "include everything", so next Friday's sales are rows too).
//  Checking a row is you saying it is done; the app places no orders. Checked,
//  it strikes through, waits 1.2 s (tap again to undo), then folds away and does
//  not come back that day. The last one folds the whole card.
//

import SwiftUI

struct SunnyThisWeek: View {
    let home: HomePayload
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// Rows ticked in the last 1.2 s: still on screen, struck through.
    @State private var pending: Set<String> = []

    /// Today's rows: every task not checked today.
    static func open(_ home: HomePayload, checked: [String: String]) -> [WeekTask] {
        (home.thisWeek?.value ?? []).filter { checked[$0.id] != home.today }
    }

    var body: some View {
        let rows = Self.open(home, checked: router.checked)
        let left = rows.filter { !pending.contains($0.id) }.count
        Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("This week").sType(.sectionTitle, tabular: false)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        Text("\(left) to do · by Fri")
                            .sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
                            .foregroundStyle(S.muted)
                            .contentTransition(.numericText(value: Double(left)))
                    }
                    .padding(.bottom, 12)
                    ForEach(rows) { r in
                        row(r)
                            .transition(.opacity.combined(with: .scale(scale: 1, anchor: .top)))
                    }
                }
                .foregroundStyle(S.ink)
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
                .sunnyGlow()
                .transition(.opacity)
            }
        }
        .animation(reduce ? .easeOut(duration: 0.2) : S.standard(0.4), value: rows.map(\.id))
    }

    // MARK: A row

    private func row(_ r: WeekTask) -> some View {
        let done = pending.contains(r.id), lit = router.nxRing == r.t
        return HStack(alignment: .center, spacing: 12) {
            Button { toggle(r) } label: {
                ZStack {
                    Circle().strokeBorder(done ? S.ink : S.muted.opacity(0.5), lineWidth: 1.5)
                    if done {
                        Circle().fill(S.ink)
                        Path { q in q.move(to: CGPoint(x: 6.5, y: 11.5)); q.addLine(to: CGPoint(x: 9.8, y: 14.6)); q.addLine(to: CGPoint(x: 15.6, y: 7.8)) }
                            .stroke(S.paper, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
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
                        (Text(r.action).foregroundStyle(lit ? S.orangeDeep : S.ink)
                         + Text(r.alt.map { " · " + $0 } ?? "").foregroundStyle(S.muted))
                            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                            .strikethrough(done)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        (Text(PF.usd(r.cost)).foregroundStyle(r.credit ? S.green : S.ink)
                         + Text(r.credit ? " credit" : "").font(SType(size: 13, weight: 500, line: 20, tracking: 0).font())
                            .foregroundStyle(S.green))
                            .sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                        Text(Self.deltaWords(r.delta))
                            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                            .foregroundStyle(S.muted)
                    }
                    .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(r.t), \(r.action)\(r.alt.map { ", " + $0 } ?? ""), \(PF.usd(r.cost))\(r.credit ? " credit" : ""), \(Self.deltaWords(r.delta))")
            .accessibilityHint("Opens \(r.t) in Positions")
        }
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .opacity(done ? 0.45 : 1)
        .animation(.easeOut(duration: 0.2), value: done)
        .animation(.easeInOut(duration: 0.4), value: lit)
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
    }

    /// "+$7.9K delta" when it adds (the design's one plus sign), "takes $36K delta" when it takes some away.
    static func deltaWords(_ v: Double) -> String {
        v >= 0 ? "+\(PF.usd(v)) delta" : "takes \(PF.usd(v)) delta"
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
