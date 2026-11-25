//
//  IncomeTab.swift
//  Sunny
//
//  The Income tab (handoff 2026-11-24 §1.4 and §2.1; SunnyIncome part page, narrow, banner bars, rung line), on the
//  same background as Positions, under the account strip, which scrolls away with the page as on the other tabs.
//  Padding 120 16 128; its own scroll position. Top to bottom, 18 apart: "Income" 28/34 bold and one grey line, the
//  realized-income banner, the logo strip (52 pt white discs; a tap brings the name's card to 96 pt from the top and
//  rings the logo; a dot only when the name needs you, red in the money, green to roll), the totals row between
//  hairlines, then a card a name: the logo 40, ticker, "Nike · weekly" (Together adds the account), price and today's
//  move, the Mon to Fri calendar, the delta line for ladder names, and every rung as a row, nothing folded.
//  The account switch dips the page as Home does (opacity .15 → 1 over .4 s, 28 pt over .5 s; Reduce Motion fades).
//

import SwiftUI

struct IncomeTab: View {
    @Environment(BriefState.self) private var brief
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    @AppStorage(BriefPrivacy.key) private var privacy = false
    @State private var pos = ScrollPosition()
    /// The logo picked on the strip (per session).
    @State private var picked: String?
    @State private var tops = IncTops()
    @State private var faded = false
    @State private var slid = false
    @State private var dipDir: CGFloat = 0
    @State private var settling: Task<Void, Never>?

    static let space = "incomeTab"
    private var pageBook: BriefAccount { brief.account }
    private var pageReady: Bool { brief.book == nil || brief.book == pageBook.book }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if brief.showsStrip {
                    AccountStrip(accounts: brief.accounts, selected: brief.account) { a in brief.pick(a) }
                }
                page
                    .padding(.horizontal, 16)
                    // The page's first line at y 120, 4 under the strip (as Home's chart).
                    .padding(.top, brief.showsStrip ? 4 - AccountStrip.lift : 14)
                    .opacity(faded ? 0.15 : 1)
                    .offset(x: slid ? 28 * dipDir : 0)
            }
            .overlay(alignment: .topTrailing) { ActivityBellSlot() }
            .padding(.bottom, 128)
            .containerRelativeFrame(.horizontal)
            .coordinateSpace(.named(Self.space))
        }
        .scrollIndicators(.hidden)
        .scrollPosition($pos)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { tops.top = $0 }
        .background(SBackground(glows: true))
        .overlay(alignment: .top) { BriefTopEdge() }
        // Tap the open tab: smooth to the top. Every rung on Home: open at the top.
        .onChange(of: router.topTick[.income]) { _, _ in withAnimation(S.moving(S.page, reduce)) { pos.scrollTo(edge: .top) } }
        .onChange(of: router.incomeTop) { _, _ in pos.scrollTo(edge: .top) }
        .onChange(of: pageBook) { _, _ in picked = nil; dip() }
        .onChange(of: pageReady) { _, ready in if ready && faded { settle(wait: false) } }
        .task {
            #if DEBUG && targetEnvironment(simulator)
            // Screens checked in the simulator: `-incPick NVDA` taps that logo; `-scroll 900` opens scrolled.
            let a = ProcessInfo.processInfo.arguments
            if let i = a.firstIndex(of: "-incPick"), i + 1 < a.count { try? await Task.sleep(for: .milliseconds(1200)); go(a[i + 1]) }
            if let y = BriefDebug.scroll { try? await Task.sleep(for: .milliseconds(1200)); pos.scrollTo(y: y) }
            #endif
        }
    }

    // MARK: The page

    @ViewBuilder private var page: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Income").sType(IncT.t(28, 34, 700, tr: -0.02), tabular: false).foregroundStyle(IncC.ink)
                    .accessibilityAddTraits(.isHeader)
                // No intro line (Nik, 25 Nov 2026: "remove both explanatory lines").
            }
            if let m = brief.incomeModel, pageReady || brief.book == nil {
                content(m)
            } else if brief.income == nil && brief.live != nil {
                Text("Income shows here once Sunny’s server sends it.")
                    .sType(IncT.t(13, 18), tabular: false).foregroundStyle(IncC.mu)
            } else {
                ProgressView().controlSize(.regular).frame(maxWidth: .infinity).padding(.top, 60)
            }
        }
    }

    @ViewBuilder private func content(_ m: IncModel) -> some View {
        if let b = m.banner {
            IncBannerView(banner: b, privacy: privacy, accounts: brief.account == .together ? brief.split.map(\.name) : [])
                .id("banner-\(brief.account.book)")
        }
        if m.names.isEmpty {
            Text("Nothing sold for income right now. Each call and put you sell shows here once IBKR reports it.")
                .sType(IncT.t(14, 20), tabular: false).foregroundStyle(IncC.mu)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            strip(m.names)
            totals(m)
            VStack(spacing: 16) {
                ForEach(m.names) { n in
                    IncNameCard(n: n, account: brief.account == .together ? n.books.joined(separator: " and ") : nil)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minY } action: { tops.y[n.t] = $0 }
                }
            }
        }
    }

    // MARK: The logo strip

    private func strip(_ names: [IncName]) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(names) { n in
                    let on = picked == n.t
                    Button { go(n.t) } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                IncLogo(t: n.t, size: 52)
                                    // Picked: a 2.5 pt ink ring inside and 2 pt of the page outside; else a 10% hairline.
                                    .overlay { Circle().strokeBorder(on ? IncC.ink : IncC.line(0.1), lineWidth: on ? 2.5 : 1) }
                                    .background { Circle().fill(IncC.ringGap).padding(on ? -2 : 0) }
                                    .animation(.easeOut(duration: 0.2), value: on)
                                if let d = n.dot {
                                    Circle().fill(IncC.of(d)).frame(width: 12, height: 12)
                                        .background(Circle().fill(IncC.page).padding(-2))
                                }
                            }
                            .frame(width: 52, height: 52)
                            Text(n.t).sType(IncT.t(13, 16, on ? 700 : 500), tabular: false).foregroundStyle(on ? IncC.ink : IncC.mu)
                                .lineLimit(1).fixedSize()
                        }
                        .frame(width: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go to \(n.co)" + (n.dot == .red ? ", in the money" : n.dot == .green ? ", ready to roll" : ""))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.top, 2).padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 4, for: .scrollContent)
        .padding(.horizontal, -4)
        .sensoryFeedback(.selection, trigger: picked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Go to a name")
    }

    /// The name's card to 96 pt under the top of the scroll area, smoothly; the logo ringed.
    private func go(_ t: String) {
        picked = t
        guard let y = tops.y[t] else { return }
        // The scroll position counts from the scroll view's own top (under the status bar, `top` from the screen's
        // top): the card's top lands 96 pt under the screen's top at y - (96 - top).
        withAnimation(S.moving(S.page, reduce)) { pos.scrollTo(y: max(0, y - 96 + tops.top)) }
    }

    // MARK: Totals

    private func totals(_ m: IncModel) -> some View {
        let items: [(String, String, Color)] = [
            ("Left to earn on these rungs", IncFmt.money(m.left, privacy), IncC.ink),
            ("Kept so far", IncFmt.money(m.kept, privacy), m.kept < -0.5 && !privacy ? IncC.red : IncC.ink),
            ("Collected", IncFmt.money(m.collected, privacy), IncC.ink),
            ("To roll", "\(m.rollCount)", m.rollCount > 0 ? IncC.green : IncC.mu),
            ("In the money", "\(m.itmCount)", m.itmCount > 0 ? IncC.red : IncC.mu)]
        return IncFlow(hSpacing: 36, vSpacing: 10) {
            ForEach(items, id: \.0) { l, v, c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.uppercased()).sType(IncT.t(12, 16, 600, tr: 0.05), tabular: false).foregroundStyle(IncC.mu)
                        .lineLimit(1).fixedSize()
                    Text(v).sType(IncT.t(17, 22, 700)).foregroundStyle(c).lineLimit(1).fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(l), \(v == "$•••" ? "hidden" : (l == "Kept so far" && m.kept < -0.5 ? "lost " : "") + v)")
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .incRule(0.08)
        .overlay(alignment: .bottom) { Rectangle().fill(IncC.line(0.08)).frame(height: 1) }
    }

    // MARK: The account switch (Home's dip)

    private func dip() {
        guard brief.showsStrip else { return }
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { dipDir = brief.switchDir; faded = true; slid = !reduce }
        settle(wait: !pageReady)
    }
    private func settle(wait: Bool) {
        settling?.cancel()
        settling = Task {
            try? await Task.sleep(for: .milliseconds(wait ? 1500 : 34))
            guard !Task.isCancelled else { return }
            withAnimation(S.switchFade) { faded = false }
            withAnimation(S.moving(S.switchMove, reduce)) { slid = false }
        }
    }
}

/// Income redraws from its own state and data, never because Home's parent did.
extension IncomeTab: Equatable {
    nonisolated static func == (_: IncomeTab, _: IncomeTab) -> Bool { true }
}

/// Where each card's top sits in the page, and where the scroll view's top sits on the screen: read on a logo tap,
/// never drawn.
final class IncTops {
    var y: [String: CGFloat] = [:]
    var top: CGFloat = 0
}

/// Items left to right, wrapping to a new line when the next does not fit (CSS flex-wrap).
struct IncFlow: Layout {
    var hSpacing: CGFloat
    var vSpacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { y += row + vSpacing; x = 0; row = 0 }
            x += z.width + hSpacing; row = max(row, z.height); maxX = max(maxX, x - hSpacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > b.width { y += row + vSpacing; x = 0; row = 0 }
            s.place(at: CGPoint(x: b.minX + x, y: b.minY + y), proposal: ProposedViewSize(z))
            x += z.width + hSpacing; row = max(row, z.height)
        }
    }
}

// MARK: - A name's card

/// Padding 16 18, radius 20, 12 apart: the header, the calendar, the delta line (ladder names), every rung as a row.
struct IncNameCard: View {
    let n: IncName
    /// Together: whose name it is.
    let account: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            IncCalendar(n: n)
            if let f = n.flip {
                IncFlipView(flip: f, bigSize: 26)
                    .padding(.vertical, 8)
                    .incRule(0.08)
                    .overlay(alignment: .bottom) { Rectangle().fill(IncC.line(0.08)).frame(height: 1) }
            }
            VStack(spacing: 0) {
                ForEach(n.lines) { IncLineRow(line: $0) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(n.t) rungs")
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .sunnyGlass(radius: 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(n.co) income")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            IncLogo(t: n.t, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(n.t).sType(IncT.t(16, 20, 700), tabular: false).foregroundStyle(IncC.ink)
                Text(n.co + (account.map { " · \($0)" } ?? "") + (n.ladder ? " · ladder" : " · weekly"))
                    .sType(IncT.t(12, 16), tabular: false).foregroundStyle(IncC.mu)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(IncFmt.f2(n.px)).sType(IncT.t(16, 20, 700)).foregroundStyle(IncC.ink)
                if let c = n.chg {
                    Text("\(c >= 0 ? "↑" : "↓") \(String(format: "%.1f", abs(c)))% today").sType(IncT.t(12, 16, 600))
                        .foregroundStyle(c >= 0 ? IncC.green : IncC.red).lineLimit(1).fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(IncSay.words("\(n.co)\(account.map { ", \($0)" } ?? ""), \(n.ladder ? "ladder" : "weekly"). \(IncFmt.f2(n.px))"
                                         + (n.chg.map { ", \($0 >= 0 ? "up" : "down") \(String(format: "%.1f", abs($0))) percent today" } ?? "")))
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - The calendar

/// Mon to Fri from this week (four weeks for ladder names, two for weekly), max 380 wide. Weekday letters 11/14; cells
/// 5 a row, 4 apart, at least 54 tall, padding 4, radius 8. The day a pill 18 tall (the first cell and a month's 1st
/// read "Nov 23"; today white with black text, bold). Each expiry day a chip a side ("72 calls", "30 puts", 17 tall,
/// radius 5, 11/17 bold): running on the track with ink text, green ready to roll and red in the money with on-colour
/// text. A cell with chips 6%, an empty one 2.5%; the day the next roll goes to dashed 35% with "next"; past days and
/// market holidays at .45.
struct IncCalendar: View {
    let n: IncName
    private let cols = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LazyVGrid(columns: cols, alignment: .leading, spacing: 4) {
                ForEach(Array(["M", "T", "W", "T", "F"].enumerated()), id: \.offset) { _, l in
                    Text(l).font(.inter(11, 600)).foregroundStyle(IncC.mu)
                        .padding(.leading, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: cols, alignment: .leading, spacing: 4) {
                ForEach(n.cal) { d in cell(d) }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: 380, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(speech)
    }

    private func cell(_ d: IncName.Day) -> some View {
        let next = d.chips.contains { $0.tone == "next" }
        let has = !d.chips.isEmpty && !next
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return VStack(alignment: .leading, spacing: 3) {
            Text(d.lbl)
                .font(.inter(11, d.today ? 700 : 500, tabular: true))
                .foregroundStyle(d.today ? IncC.onColor : d.past ? IncC.mu : IncC.quiet)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(d.today ? IncC.ink : .clear))
            ForEach(Array(d.chips.enumerated()), id: \.offset) { _, c in chip(c) }
            if d.closed && d.chips.isEmpty {
                Text("closed").font(.inter(11, 500)).foregroundStyle(IncC.mu).padding(.horizontal, 5)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .background(shape.fill(IncC.line(has ? 0.06 : 0.025)))
        .overlay {
            if next { shape.strokeBorder(IncC.line(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2])) }
        }
        .opacity(d.past || d.closed ? 0.45 : 1)
    }

    private func chip(_ c: IncName.Chip) -> some View {
        let bg: Color = c.tone == "itm" ? IncC.red : c.tone == "roll" ? IncC.green : c.tone == "next" ? .clear : IncC.track
        let fg: Color = c.tone == "itm" || c.tone == "roll" ? IncC.onColor : c.tone == "next" ? IncC.mu : IncC.ink
        return Text(c.t).font(.inter(11, 700, tabular: true)).foregroundStyle(fg)
            .lineLimit(1).truncationMode(.tail)
            .padding(.horizontal, 5)
            .frame(height: 17)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(bg))
    }

    /// "NVDA calendar: Nov 27: 3 calls and 2 puts; Dec 7: the next one. Today is Tue Nov 24."
    private var speech: String {
        let said = n.cal.compactMap { d -> String? in
            guard !d.chips.isEmpty else { return nil }
            if d.chips.contains(where: { $0.tone == "next" }) { return "\(IncFmt.md(d.d)): the next one" }
            return "\(IncFmt.md(d.d)): " + d.chips.map { $0.t + ($0.tone == "itm" ? " in the money" : $0.tone == "roll" ? " ready to roll" : "") }.joined(separator: " and ")
        }
        let today = n.cal.first { $0.today }.map { " Today is \(IncFmt.dmd($0.d))." } ?? ""
        return IncSay.words("\(n.t) calendar: " + (said.isEmpty ? "nothing sold" : said.joined(separator: "; ")) + "." + today)
    }
}
