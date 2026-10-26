//
//  SunnyGammaTab.swift
//  Sunny
//
//  Blocks 12c and 13h (handoff 32, 25 Oct 2026) · the Gamma tab: one name at a time under a ticker strip,
//  book names first (names with To do first, an orange dot), then a Watchlist divider and the Home
//  watchlist as outlined chips. As designed: one scroll, the strip scrolls with the page. Tap a chip or swipe
//  sideways; the page slides (no fade) and, scrolled, the title reads "BABA's Gamma" (Nik, 26 Oct 2026). The
//  name carries over to Insights. A book name gets the whole page (GammaPage); a watchlist name gets its
//  open-interest walls only, tagged so.
//

import SwiftUI

struct SunnyGammaTab: View {
    let store: HomeStore
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var top = ScrollPosition()
    /// Which way the last switch went, for the slide.
    @State private var forward = true
    /// Scrolled: the small title names the ticker ("BABA's Gamma", Nik 26 Oct 2026).
    @State private var scrolled = false

    var body: some View {
        ZStack {
            SBackground()
            if let home = store.home { screen(home) } else { Color.clear.navigationTitle("Gamma") }
        }
        .navigationBarTitleDisplayMode(.large)
    }

    /// Book names (To do first), then the watchlist names not held.
    static func names(_ home: HomePayload, words: HomePayload?) -> (book: [PName], watch: [String]) {
        let book = PNames.build(home, orderFrom: words)
        let held = Set(book.map(\.t))
        return (book, home.watchlist.map(\.ticker).filter { !held.contains($0) })
    }

    /// Names with a full tape read that are not in the book (Nik's rule 6: the held names plus TSLA). They sit with
    /// the book names in the strip (design 12c) and open the full Gamma page, with no plan.
    static let tapeNames = ["TSLA"]

    private func screen(_ home: HomePayload) -> some View {
        let (book, watch0) = Self.names(home, words: store.words)
        let tape = Self.tapeNames.filter { t in !book.contains { $0.t == t } }
        let watch = watch0.filter { !tape.contains($0) }
        let all = book.map(\.t) + tape + watch
        let t = router.focus.flatMap { all.contains($0) ? $0 : nil } ?? all.first ?? ""
        let todo = book.filter(\.hasTodo).count
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                strip(book: book, tape: tape, watch: watch, on: t)
                Group {
                    if book.contains(where: { $0.t == t }) || tape.contains(t) {
                        GammaPage(t: t, home: home, name: book.first { $0.t == t })
                    } else if !t.isEmpty {
                        GammaWatchPage(t: t, home: home)
                    }
                }
                .id(t)
                // A plain slide, no fade (Nik, 26 Oct 2026).
                .transition(reduce ? .opacity : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                                            removal: .move(edge: forward ? .leading : .trailing)))
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($top)
        // The soft fade under the title, as on Positions (Nik, 26 Oct 2026: no hard line).
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 50 } action: { _, v in scrolled = v }
        .onChange(of: router.topTick[.gamma]) { _, _ in withAnimation(reduce ? nil : S.standard(0.45)) { top.scrollTo(edge: .top) } }
        .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { g in
            // A clear sideways swipe changes the name (12c: pages swipe sideways).
            guard abs(g.translation.width) > 80, abs(g.translation.width) > 2 * abs(g.translation.height),
                  let i = all.firstIndex(of: t) else { return }
            let j = g.translation.width < 0 ? i + 1 : i - 1
            guard all.indices.contains(j) else { return }
            select(all[j], forward: j > i)
        })
        // Scrolled: "BABA's Gamma" and no line under it (Nik, 26 Oct 2026).
        .navigationTitle(scrolled && !t.isEmpty ? "\(t)'s Gamma" : "Gamma")
        .navigationSubtitle(scrolled ? "" : "\(PWords.n(book.count + tape.count, "name"))" + (todo > 0 ? " · \(todo) with To do" : "") + (watch.isEmpty ? "" : " · \(watch.count) watching"))
    }

    private func select(_ t: String, forward f: Bool) {
        UISelectionFeedbackGenerator().selectionChanged()
        forward = f
        withAnimation(reduce ? .easeOut(duration: 0.2) : S.standard(0.4)) { router.focus = t }
    }

    // MARK: The ticker strip: 36 tall, book chips filled, watchlist chips outlined, the selected one ink

    private func strip(book: [PName], tape: [String], watch: [String], on: String) -> some View {
        let all = book.map(\.t) + tape + watch
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(book) { n in chip(n.t, dot: n.hasTodo, outlined: false, on: n.t == on, all: all) }
                    ForEach(tape, id: \.self) { x in chip(x, dot: false, outlined: false, on: x == on, all: all) }
                    if !watch.isEmpty {
                        Text("Watchlist").sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted).padding(.horizontal, 4)
                        ForEach(watch, id: \.self) { w in chip(w, dot: false, outlined: true, on: w == on, all: all) }
                    }
                }
                .padding(.horizontal, S.margin)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            // The strip scrolls to the selected chip rather than jumping (Nik, 26 Oct 2026).
            .onChange(of: on) { _, t in withAnimation(reduce ? nil : S.standard(0.35)) { proxy.scrollTo(t, anchor: .center) } }
        }
    }

    private func chip(_ t: String, dot: Bool, outlined: Bool, on: Bool, all: [String]) -> some View {
        Button { if !on, let i = all.firstIndex(of: router.focus ?? all.first ?? ""), let j = all.firstIndex(of: t) { select(t, forward: j > i) } else if !on { select(t, forward: true) } } label: {
            HStack(spacing: 6) {
                if dot { Circle().fill(S.orange).frame(width: 7, height: 7) }
                Text(t).sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false)
                    .foregroundStyle(on ? S.paper : S.ink)
            }
            .padding(.horizontal, 14).frame(height: 36)
            .background {
                if on { Capsule().fill(S.ink) }
                else if outlined { Capsule().strokeBorder(S.line, lineWidth: 1) }
                else { Capsule().fill(S.tileWalls).overlay(Capsule().strokeBorder(S.line, lineWidth: 0.5)) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(POpacityPress())
        .id(t)
        .accessibilityLabel(t + (dot ? ", has To do" : "") + (outlined ? ", watchlist" : ""))
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

/// A watchlist name: open-interest walls only, never tape labels (Nik, 25 Oct 2026).
struct GammaWatchPage: View {
    let t: String
    let home: HomePayload
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t).sType(SType(size: 28, weight: 800, line: 32, tracking: -0.01), tabular: false).foregroundStyle(S.ink)
                Text("OI only, no tape labels · not in your book")
                    .sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false)
                    .foregroundStyle(S.orangeDeep)
                Text("Walls from open interest at the last close. The tape is read for the names you hold.")
                    .sType(SType(size: 13, weight: 400, line: 18, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, S.margin + 20)
            SunnyWalls(t: t, px: home.watchlist.first { $0.ticker == t }?.price ?? 0, today: home.today, sells: nil, tags: [:], embedded: true)
                .padding(.horizontal, S.margin - 16 + 4)
        }
    }
}
