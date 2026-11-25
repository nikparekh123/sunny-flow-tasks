//
//  IncToday.swift
//  Sunny
//
//  Income today (handoff 2026-11-24 §1.3; SunnyIncome part today, narrow, rung need): the first card in Home's
//  "2 · Your book" on every moment, only what needs you. The header "Income today" with "2 need you" (red if anything
//  is in the money, else green; "All quiet" grey) and the marks' time under it, the Every rung pill (34 high, a 1 pt
//  16% ring) that opens the Income tab at the top, the ladder names' delta lines, then In the money · you decide (red)
//  and Ready to roll (green), a row a rung, and the grey footer: how many more run on their own and the nearest to a
//  roll. Card padding 16 16 4, radius 22, sections 10 apart, on the flat card (SunnyGlass).
//  IWM's daily row waits until Nicolay trades IWM or Nik sets its rule (D4).
//

import SwiftUI

struct IncTodayCard: View {
    @Environment(BriefState.self) private var brief
    @Environment(HomeRouter.self) private var router

    var body: some View {
        if let m = brief.incomeModel {
            content(m)
        }
    }

    private func content(_ m: IncModel) -> some View {
        let n = m.needCount
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    // "Income today  2 need you": wraps under when the text is large.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) { head; need(n, m) }
                        VStack(alignment: .leading, spacing: 0) { head; need(n, m) }
                    }
                    if let s = Self.marks(brief) {
                        Text(s).sType(IncT.t(13, 18)).foregroundStyle(IncC.mu)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    router.tab = .income
                    router.incomeTop += 1
                } label: {
                    Text("Every rung ›").sType(IncT.t(13, 18, 600), tabular: false).foregroundStyle(IncC.ink)
                        .padding(.horizontal, 14).frame(height: 34)
                        .overlay(Capsule().strokeBorder(IncC.line(0.16), lineWidth: 1))
                        .contentShape(.capsule)
                }
                .buttonStyle(SunnyTabPress())
                .accessibilityLabel("Every rung")
                .accessibilityHint("Opens the Income tab")
            }
            if !m.flips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(m.flips.enumerated()), id: \.offset) { _, f in IncFlipView(flip: f, bigSize: 17) }
                }
                .padding(.top, 12).padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .incRule(0.08)
            }
            if !m.itm.isEmpty { group("In the money · you decide · \(m.itm.count)", IncC.red, m.itm) }
            if !m.roll.isEmpty { group("Ready to roll · \(m.roll.count)", IncC.green, m.roll) }
            if n == 0 {
                Text("Nothing needs you today.").sType(IncT.t(15, 20, 600), tabular: false).foregroundStyle(IncC.ink)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .incRule(0.12)
            }
            if m.quietCount > 0 {
                Text(Self.footer(m)).sType(IncT.t(13, 18)).foregroundStyle(IncC.mu)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .incRule(0.08)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 4, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .sunnyGlass(radius: 22)
        .padding(.horizontal, S.margin)
    }

    private var head: some View {
        Text("Income today").sType(IncT.t(17, 22, 700, tr: -0.01), tabular: false).foregroundStyle(IncC.ink)
            .accessibilityAddTraits(.isHeader)
    }
    private func need(_ n: Int, _ m: IncModel) -> some View {
        Text(n == 0 ? "All quiet" : n == 1 ? "1 needs you" : "\(n) need you")
            .sType(IncT.t(15, 20, 600), tabular: false)
            .foregroundStyle(!m.itm.isEmpty ? IncC.red : n > 0 ? IncC.green : IncC.mu)
    }

    /// A group under its 12/16 uppercase title in its colour, rows as on the Income tab with the ticker.
    private func group(_ title: String, _ c: Color, _ rows: [IncLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).sType(IncT.t(12, 16, 700, tr: 0.05), tabular: false).foregroundStyle(c)
                .padding(.top, 10).padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .incRule(0.12)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { IncLineRow(line: $0) }
        }
    }

    /// "17 more rungs run on their own · nearest to a roll: NKE 36 call Oct 30 at 73%."
    static func footer(_ m: IncModel) -> String {
        let q = m.quietCount
        return "\(q) more \(q == 1 ? "rung runs" : "rungs run") on their own" + (m.near.map { " · nearest to a roll: \($0)" } ?? "") + "."
    }

    /// The marks' time: "Tue Nov 24 close" for marks at or after the close (or an earlier day), else
    /// "Tue Nov 24 · 12:40 PM ET".
    static func marks(_ brief: BriefState) -> String? {
        guard let d = brief.fresh.marks else { return nil }
        let n = MarketClock.ny(d), today = MarketClock.ny(SClock.now())
        if n.date < today.date || n.minutes >= MarketClock.closeMinutes(n.date, brief.calendar) { return "\(IncFmt.dmd(n.date)) close" }
        let f = DateFormatter(); f.timeZone = MarketClock.ny; f.dateFormat = "h:mm a"
        return "\(IncFmt.dmd(n.date)) · \(f.string(from: d)) ET"
    }
}
