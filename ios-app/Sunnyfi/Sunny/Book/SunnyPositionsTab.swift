//
//  SunnyPositionsTab.swift
//  Sunny
//
//  Blocks 12 and 12a (handoff 30, 22 Oct 2026) · the Positions tab: the native
//  nav bar (large title, a subtitle, the filter menu), the book's totals in one
//  sideways row, one glass card per name with To do first, then Inventory.
//  The chrome is the system's; only what sits inside the cards is custom.
//

import SwiftUI

struct SunnyPositionsTab: View {
    let store: HomeStore
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// The totals' view: one tap turns every number together (time value, % change, $ change).
    @State private var mode = 0
    @State private var top = ScrollPosition()

    var body: some View {
        @Bindable var router = router
        ZStack {
            SBackground()
            if let home = store.home { screen(home) }
        }
        .navigationTitle("Positions")
        .navigationBarTitleDisplayMode(.large)
        // All walls on a card (13d): the Walls screen for that name, the system's push and back.
        .navigationDestination(item: $router.walls) { t in walls(t) }
        .environment(\.livePulse, store.livePulse)
        .environment(\.changedLegs, store.changedLegs)
    }

    private func screen(_ home: HomePayload) -> some View {
        let words = store.words ?? home
        let all = PNames.build(home, orderFrom: words)
        let shown = all.filter { $0.matches(router.filter) }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if all.isEmpty {
                        empty
                    } else {
                        totals(PMath.legs(home))
                            .padding(.bottom, 12)
                        if shown.isEmpty {
                            Text(router.filter.none)
                                .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                                .foregroundStyle(S.muted)
                                .padding(.bottom, 12)
                        }
                        SunnyPositionCards(home: home, names: shown)
                        SunnyInventory(home: home, words: words)
                            .id("inventory")
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, S.margin)
                .padding(.top, 4)
                // The floating tab bar never covers the last card (block 12a: 120 pt under it).
                .padding(.bottom, 40)
                .animation(reduce ? nil : S.standard(0.35), value: shown.map(\.t))
            }
            .scrollIndicators(.hidden)
            .scrollPosition($top)
            .onChange(of: router.topTick[.positions]) { _, _ in withAnimation(reduce ? nil : S.standard(0.45)) { top.scrollTo(edge: .top) } }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable { await store.refresh(.pull) }
            // A card opened from a tap: a smooth scroll, the card 16 pt under the nav bar.
            .onChange(of: router.scrollTo) { _, id in
                guard let id else { return }
                withAnimation(reduce ? nil : S.standard(0.45)) { proxy.scrollTo(id, anchor: .top) }
                router.scrollTo = nil
            }
        }
        .navigationSubtitle(subtitle(all, shown: shown.count))
        .toolbar {
            if !all.isEmpty {
                // While a filter is on the button is its own ink circle, not inside the bar's glass.
                ToolbarItem(placement: .topBarTrailing) { filterMenu(all) }
                    .sharedBackgroundVisibility(router.filter != .all ? .hidden : .automatic)
            }
        }
    }

    /// The Walls screen: opens on next Friday's expiry; the To do chains are tagged (13d).
    @ViewBuilder private func walls(_ t: String) -> some View {
        if let home = store.home {
            let w = home.ways?.value?[t]
            let held = Set((home.writes.names.first { $0.ticker == t }?.pkg?.held ?? []).filter { $0.ty == "oc" }.map(\.exp))
            let buys = Set([w?.buy.calls?.exp, w?.buy.puts?.exp].compactMap { $0 }).subtracting(held)
            let tags = Dictionary(grouping: [(w?.sell.exp, "Your sells")].compactMap { e, s in e.map { ($0, s) } }
                + held.map { ($0, "Your hedge · calls held") } + buys.map { ($0, "Your hedge · new buys") }, by: \.0)
                .mapValues { $0.map(\.1) }
            let px = PNames.build(home, orderFrom: store.words ?? home).first { $0.t == t }?.px ?? 0
            SunnyWalls(t: t, px: px, today: home.today, sells: w?.sell.exp, tags: tags)
        }
    }

    /// "7 names · 5 with To do", or while a filter is on "Stock up · 4 of 7 names".
    private func subtitle(_ all: [PName], shown: Int) -> String {
        let names = PWords.n(all.count, "name"), todo = all.filter(\.hasTodo).count
        if router.filter != .all { return "\(router.filter.title) · \(shown) of \(names)" }
        return names + (todo > 0 ? " · \(todo) with To do" : "")
    }

    // MARK: Totals (block 12): always the whole book, a filter never changes them

    private func totals(_ L: [PLeg]) -> some View {
        let word = ["time value", "% change", "$ change"][mode]
        let groups: [(String, [(String, [PLeg])])] = [
            ("Bought", [("Long calls", L.filter { !$0.sold && $0.call && !$0.up }),
                        ("Hedge calls", L.filter { !$0.sold && $0.call && $0.up }),
                        ("Puts", L.filter { !$0.sold && !$0.call })]),
            ("Sold", [("Calls", L.filter { $0.sold && $0.call }),
                      ("Puts", L.filter { $0.sold && !$0.call })]),
        ]
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { gi, g in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(g.0).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false)
                            .foregroundStyle(S.ink)
                            .accessibilityAddTraits(.isHeader)
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(g.1.enumerated()), id: \.offset) { j, it in
                                total(group: g.0, name: it.0, PTotals(it.1), word: word)
                                    .padding(.leading, j > 0 ? 16 : 0)
                                    .padding(.trailing, 16)
                                    .overlay(alignment: .leading) { if j > 0 { Rectangle().fill(S.pRule).frame(width: 1) } }
                            }
                        }
                    }
                    .padding(.leading, gi > 0 ? 16 : 0)
                    .overlay(alignment: .leading) { if gi > 0 { Rectangle().fill(S.pRule).frame(width: 1) } }
                }
            }
            .padding(.leading, S.margin).padding(.trailing, 40)
            .padding(.top, 2).padding(.bottom, 6)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -S.margin)
        // The row fades out over its last 36 pt.
        .mask {
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 36)
            }
        }
    }

    private func total(group: String, name: String, _ A: PTotals, word: String) -> some View {
        let v: Double = [A.tv, abs(A.pct), abs(A.g)][mode]
        let fmt: (Double) -> String = mode == 1 ? { PF.pct($0) } : { PF.usd($0) }
        let c = mode == 0 ? S.ink : (A.g >= 0 ? S.green : S.red)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduce ? nil : .smooth(duration: S.roll)) { mode = (mode + 1) % 3 }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(fmt(v)).sType(SType(size: 22, weight: 700, line: 28, tracking: -0.01))
                    .foregroundStyle(c)
                    .contentTransition(.numericText(value: v))
                Text("\(name) · \(word)").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted)
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(POpacity())
        .accessibilityLabel("\(group) \(name.lowercased()), \(word) \(fmt(v))")
        .accessibilityHint("Tap for the next view")
    }

    // MARK: Filter (block 12): one native toolbar menu, one filter at a time

    private func filterMenu(_ all: [PName]) -> some View {
        let on = router.filter != .all
        // Toggles, not an inline Picker: inside a menu the picker drops its section headers and the
        // count under each option. One filter at a time; picking the one that is on goes back to all.
        func opt(_ f: PFilter, _ title: String) -> some View {
            Toggle(isOn: Binding(get: { router.filter == f },
                                 set: { v in withAnimation(reduce ? nil : S.standard(0.35)) { router.filter = v ? f : .all } })) {
                Text(title)
                Text(PWords.n(all.filter { $0.matches(f) }.count, "name"))
            }
        }
        return Menu {
            Section {
                opt(.all, "All names")
                opt(.todo, "To do")
            }
            Section("The stock today") {
                opt(.up, "Stock up")
                opt(.down, "Stock down")
            }
            Section("Calls that kept at least") {
                ForEach([25, 50, 75, 90], id: \.self) { p in opt(.kept(p), "\(p)% of premium") }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
        .modifier(PFilterButton(on: on))
        .accessibilityLabel(on ? "Filter, \(router.filter.title) is on" : "Filter")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No open positions").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
            Text("Calls and puts you sell or buy show up here.")
                .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false)
                .foregroundStyle(S.muted)
        }
        .foregroundStyle(S.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: S.rCard))
    }
}

/// While a filter is on, the toolbar button turns prominent in ink (block 12).
private struct PFilterButton: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        // A menu takes a button style only as a button-style menu.
        if on { content.menuStyle(.button).buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(S.ink) } else { content }
    }
}

/// Press dims to 60%.
private struct POpacity: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
