//
//  SundialTab.swift
//  Sunny
//
//  The Sundial tab (handoff 2026-11-27 README §2; SunnyIncomeBoard.dc.html narrow, Round 207c): the board from Sundial
//  1.0, the five columns as sections down the page in the web's order, To sell first. Sundial decides what to sell,
//  Nik decides what to buy. It replaces the Income tab's realized banner and calendar.
//  Under the account strip (it scrolls away with the page as on the other tabs). Top to bottom: "Sundial" 30 bold
//  with whose book and when beside it, the name chips (All, then each name; they refetch), the hero (November so far,
//  48), then To sell · Close · Working · Expiring today · Banked this week, 32 apart.
//  Data: SundialStore, on appear, on an account or name change, and every 60 s while the market is open.
//  The account switch dips the page as Home does (opacity .15 → 1 over .4 s, 28 pt over .5 s; Reduce Motion fades).
//

import SwiftUI

struct SundialTab: View {
    @Environment(BriefState.self) private var brief
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var store = SundialStore.shared
    @State private var pos = ScrollPosition()
    /// The name chip (per session); "all" is All. Back to All when the account changes.
    @State private var name = "all"
    @State private var faded = false
    @State private var slid = false
    @State private var dipDir: CGFloat = 0
    @State private var settling: Task<Void, Never>?

    private var acct: String { SDF.account(brief.account) }
    /// The chip before this one: its board shows, faded, until this one arrives.
    @State private var prevName = "all"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if brief.showsStrip {
                    AccountStrip(accounts: brief.accounts, selected: brief.account) { a in brief.pick(a) }
                }
                page
                    .padding(.horizontal, 16)
                    .padding(.top, brief.showsStrip ? 4 - AccountStrip.lift : 14)
                    .opacity(faded ? 0.15 : 1)
                    .offset(x: slid ? 28 * dipDir : 0)
            }
            .overlay(alignment: .topTrailing) { ActivityBellSlot() }
            .padding(.bottom, 128)
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($pos)
        .background(SBackground(glows: true))
        .overlay(alignment: .top) { BriefTopEdge() }
        // Tap the open tab: smooth to the top. Every rung on Home: open at the top.
        .onChange(of: router.topTick[.income]) { _, _ in withAnimation(S.moving(S.page, reduce)) { pos.scrollTo(edge: .top) } }
        .onChange(of: router.incomeTop) { _, _ in pos.scrollTo(edge: .top) }
        .onChange(of: brief.account) { _, _ in name = "all"; prevName = "all"; dip() }
        .onChange(of: name) { old, _ in prevName = old }
        .onChange(of: store.board(acct, name) != nil) { _, ready in if ready && faded { settle(wait: false) } }
        #if DEBUG && targetEnvironment(simulator)
        // Screens checked in the simulator: `-scroll 900` opens scrolled.
        .task { if let y = BriefDebug.scroll { try? await Task.sleep(for: .milliseconds(1500)); pos.scrollTo(y: y) } }
        #endif
        // On appear, on a new account or name, then every minute while the market is open (to 30 min after the close).
        .task(id: SundialStore.key(acct, name)) {
            #if DEBUG && targetEnvironment(simulator)
            if let n = Self.debugName, name == "all", n != "all" { name = n; return }
            #endif
            await store.load(acct, name)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                if Self.live(store.board(acct, name)) { await store.load(acct, name) }
            }
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    /// `-sdName NVDA` opens on that name's chip.
    private static let debugName: String? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-sdName"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }()
    #endif

    /// The market open (9:00 New York to 30 minutes after the close) on a trading day.
    private static func live(_ b: SDBoard?) -> Bool {
        guard let b, b.open == true else { return false }
        let close = b.closeAt.flatMap(SDF.hmParts).map { $0.0 * 60 + $0.1 } ?? 960, m = SDF.nyMinutes()
        return m >= 9 * 60 && m <= close + 30
    }

    // MARK: The page

    @ViewBuilder private var page: some View {
        if let b = store.board(acct, name) {
            SundialBoardView(board: b, account: brief.account, name: $name)
        } else if let b = store.board(acct, prevName) {
            SundialBoardView(board: b, account: brief.account, name: $name).opacity(0.5).allowsHitTesting(true)
        } else if store.failed.contains(SundialStore.key(acct, name)) {
            VStack(alignment: .leading, spacing: 18) {
                SundialHead.title
                Text("Sundial could not load just now. It tries again in a minute.")
                    .sType(IncT.t(13, 18), tabular: false).foregroundStyle(SDC.mu)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                SundialHead.title
                ProgressView().controlSize(.regular).frame(maxWidth: .infinity).padding(.top, 60)
            }
        }
    }

    // MARK: The account switch (Home's dip)

    private func dip() {
        guard brief.showsStrip else { return }
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { dipDir = brief.switchDir; faded = true; slid = !reduce }
        settle(wait: store.board(acct, "all") == nil)
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

/// Sundial redraws from its own state and data, never because Home's parent did.
extension SundialTab: Equatable {
    nonisolated static func == (_: SundialTab, _: SundialTab) -> Bool { true }
}

// MARK: - The board

struct SundialBoardView: View {
    let board: SDBoard
    let account: BriefAccount
    @Binding var name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SundialHead(board: board, account: account, name: $name)
            VStack(alignment: .leading, spacing: 32) {
                SDToSell(board: board)
                SDCloseColumn(board: board)
                SDWorkingColumn(board: board)
                SDExpiringColumn(board: board)
                SDBankedColumn(board: board)
            }
        }
    }
}

/// The header: the title, whose book and when, the name chips and the one hero (README §2.1: nothing else).
struct SundialHead: View {
    let board: SDBoard
    let account: BriefAccount
    @Binding var name: String

    static var title: some View {
        Text("Sundial").sType(IncT.t(30, 33, 700, tr: -0.01), tabular: false).foregroundStyle(SDC.ink)
            .accessibilityAddTraits(.isHeader)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) { Self.title; Spacer(minLength: 0); who }
                VStack(alignment: .leading, spacing: 6) { Self.title; who }
            }
            chips
            VStack(alignment: .leading, spacing: 8) {
                Text(board.month?.label ?? "This month").sType(IncT.t(13, 16, 500), tabular: false).foregroundStyle(SDC.mu)
                Text(SDF.signedT(board.month?.amount ?? 0)).sType(IncT.t(48, 48, 700, tr: -0.02).heroic).foregroundStyle(SDC.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "Nicolay · Fri Nov 27 · 3:46 PM": the board's time from the same clock as Expiring's.
    private var who: some View {
        TimelineView(.everyMinute) { tl in
            Text("\(board.book ?? account.name) · \(SDF.whoLine(tl.date))")
                .sType(IncT.t(13, 16), tabular: false).foregroundStyle(SDC.mu).lineLimit(1)
        }
    }

    private var chips: some View {
        let list = [("all", "All")] + (board.names ?? []).map { ($0.t, $0.name ?? $0.t) }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(list, id: \.0) { k, t in
                    let on = name == k
                    Button { name = k } label: {
                        Text(t).sType(IncT.t(15, 20, 500), tabular: false)
                            .foregroundStyle(on ? SF.chipOnInk : SDC.ink)
                            .padding(.horizontal, 16).frame(height: 36)
                            .background(Capsule().fill(on ? SF.chipOn : Color.clear))
                            .overlay { if !on { Capsule().strokeBorder(SDC.chipOff, lineWidth: 1) } }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
        .sensoryFeedback(.selection, trigger: name)
    }
}
