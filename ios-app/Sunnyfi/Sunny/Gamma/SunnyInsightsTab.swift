//
//  SunnyInsightsTab.swift
//  Sunny
//
//  Block 14d (handoff 32) · the Insights tab: All first (the first time), then one name at a time, the name
//  carried over from Gamma. All: the verdict with to do · to watch · quiet, then what changed per name since the
//  last session, most pressing first (the hedge after a name's other Watch points), the rest folded. A name: the
//  verdict and chips, six tagged points in the design's order (Helps · Watch · Neutral · Hurts puts), the long
//  term, then To do and Gamma. A watchlist name: its walls in one card. Rules write the words for now (rule 9).
//

import SwiftUI

struct SunnyInsightsTab: View {
    let store: HomeStore
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var top = ScrollPosition()
    /// Which way the last switch went, for the slide.
    @State private var forward = true
    /// Scrolled: the small title names the ticker ("BABA's Insights", Nik 26 Oct 2026).
    @State private var scrolled = false

    var body: some View {
        ZStack {
            SBackground()
            if let home = store.home { screen(home) } else { Color.clear.navigationTitle("Insights") }
        }
        .navigationBarTitleDisplayMode(.large)
    }

    /// As designed: one scroll, the strip scrolls with the page. Tap a chip or swipe sideways; the page slides
    /// (no fade, Nik 26 Oct 2026).
    private func screen(_ home: HomePayload) -> some View {
        let (book, watch) = SunnyGammaTab.names(home, words: store.words)
        let pages = ["All"] + book.map(\.t) + watch
        let on0 = router.insightsAll ? "All" : (router.focus ?? "All")
        let on = pages.contains(on0) ? on0 : "All"
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                strip(["All"] + book.map(\.t), watch, on: on, pages: pages, todo: Set(book.filter(\.hasTodo).map(\.t)))
                Group {
                    if on == "All" { all(home, book) }
                    else if let n = book.first(where: { $0.t == on }) { name(home, n) }
                    else { watchCard(home, on) }
                }
                .id(on)
                .transition(reduce ? .opacity : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading),
                                                            removal: .move(edge: forward ? .leading : .trailing)))
            }
            .padding(.top, 4).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($top)
        // The soft fade under the title, as on Positions (Nik, 26 Oct 2026: no hard line).
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 50 } action: { _, v in scrolled = v }
        .onChange(of: router.topTick[.insights]) { _, _ in withAnimation(reduce ? nil : S.standard(0.45)) { top.scrollTo(edge: .top) } }
        .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { g in
            // A clear sideways swipe moves to the next or previous name.
            guard abs(g.translation.width) > 80, abs(g.translation.width) > 2 * abs(g.translation.height),
                  let i = pages.firstIndex(of: on) else { return }
            let j = g.translation.width < 0 ? i + 1 : i - 1
            guard pages.indices.contains(j) else { return }
            select(pages[j], forward: j > i)
        })
        // Scrolled: "BABA's Insights" and no line under it (Nik, 26 Oct 2026).
        .navigationTitle(scrolled && on != "All" ? "\(on)'s Insights" : "Insights")
        .navigationSubtitle(scrolled ? "" : "Updated " + updated(home))
    }

    private func select(_ t: String, forward f: Bool) {
        UISelectionFeedbackGenerator().selectionChanged()
        forward = f
        withAnimation(reduce ? .easeOut(duration: 0.2) : S.standard(0.4)) {
            if t == "All" { router.insightsAll = true } else { router.insightsAll = false; router.focus = t }
        }
    }

    private func updated(_ home: HomePayload) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: (store.words ?? home).builtAt) ?? ISO8601DateFormatter().date(from: (store.words ?? home).builtAt)
        guard let d else { return "today" }
        let df = DateFormatter(); df.timeZone = TimeZone(identifier: "America/New_York"); df.dateFormat = "EEE h:mm a"
        return df.string(from: d)
    }

    private func strip(_ book: [String], _ watch: [String], on: String, pages: [String], todo: Set<String>) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(book, id: \.self) { t in chip(t, dot: todo.contains(t), outlined: false, on: t == on, pages: pages).id(t) }
                    if !watch.isEmpty {
                        Text("Watchlist").sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted).padding(.horizontal, 4)
                        ForEach(watch, id: \.self) { t in chip(t, dot: false, outlined: true, on: t == on, pages: pages).id(t) }
                    }
                }
                .padding(.horizontal, S.margin).padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            // The strip scrolls to the selected chip rather than jumping (Nik, 26 Oct 2026).
            .onChange(of: on) { _, t in withAnimation(reduce ? nil : S.standard(0.35)) { proxy.scrollTo(t, anchor: .center) } }
        }
    }

    private func chip(_ t: String, dot: Bool, outlined: Bool, on: Bool, pages: [String]) -> some View {
        Button {
            guard !on else { return }
            let cur = router.insightsAll ? "All" : (router.focus ?? "All")
            select(t, forward: (pages.firstIndex(of: t) ?? 0) > (pages.firstIndex(of: cur) ?? 0))
        } label: {
            HStack(spacing: 6) {
                if dot { Circle().fill(S.orange).frame(width: 7, height: 7) }
                Text(t).sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(on ? S.paper : S.ink)
            }
            .padding(.horizontal, 14).frame(height: 36)
            .background {
                if on { Capsule().fill(S.ink) }
                else if outlined { Capsule().strokeBorder(S.line, lineWidth: 1) }
                else { Capsule().fill(S.tileWalls).overlay(Capsule().strokeBorder(S.line, lineWidth: 0.5)) }
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(POpacityPress())
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: All: the verdict and what changed, most important first (sunny-home `insights_all`)

    private func all(_ home: HomePayload, _ book: [PName]) -> some View {
        let a = home.insightsAll?.value
        return LazyVStack(alignment: .leading, spacing: 16) {
            verdictCard(label: "This week · all names", text: a?.verdict ?? "Every name is on plan this week.") {
                if let a {
                    pill("\(a.todo) to do", tone: "todo")
                    pill("\(a.watch) to watch", tone: "quiet")
                    pill("\(a.quiet) quiet", tone: "good")
                }
            }
            SCard {
                VStack(alignment: .leading, spacing: 0) {
                    Text("What changed across your names").sType(SType(size: 22, weight: 700, line: 28, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Most important first. Tap one to open that name.").sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted).padding(.top, 4).padding(.bottom, 12)
                    ForEach(a?.rows ?? [], id: \.t) { r in
                        Button { withAnimation(S.standard(0.3)) { router.insightsAll = false; router.focus = r.t } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    HStack(spacing: 5) {
                                        if r.todo { Circle().fill(S.orange).frame(width: 7, height: 7) }
                                        Text(r.t).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false)
                                    }
                                    .foregroundStyle(S.ink).padding(.horizontal, 9).frame(height: 26).background(Capsule().fill(S.track))
                                    Spacer(minLength: 6)
                                    tag(r.tag)
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(S.muted)
                                }
                                Text(r.lead).sType(SType(size: 17, weight: 600, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                marked(r.body).sType(SType(size: 16, weight: 400, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                            }
                            .padding(.vertical, 14).contentShape(Rectangle())
                        }
                        .buttonStyle(POpacityPress())
                        .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
                        .accessibilityHint("Opens \(r.t)")
                    }
                    if let f = a?.folded, !f.isEmpty {
                        Text("Nothing new: " + f.joined(separator: ", "))
                            .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
                            .padding(.vertical, 14)
                            .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
                    }
                }
            }
            .padding(.horizontal, S.margin)
        }
    }

    // MARK: A name: the verdict and chips, what matters for the trade, the long term, then To do and Gamma

    private func name(_ home: HomePayload, _ n: PName) -> some View {
        let ins = home.writes.names.first { $0.ticker == n.t }?.insights?.value
        return VStack(alignment: .leading, spacing: 16) {
            (Text(ins?.name ?? n.t).foregroundStyle(S.ink) + Text(" This week").foregroundStyle(S.muted))
                .sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false)
                .padding(.horizontal, S.margin)
            if let v = ins?.v2 {
                verdictCard(label: "This week", text: v.verdict) {
                    ForEach(v.chips, id: \.k) { c in pill("\(c.k): \(c.v)", tone: c.tone) }
                }
                SCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("What matters for your trade").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        Text("Most important first. The tag says how each one affects selling calls.").sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 4).padding(.bottom, 10)
                        ForEach(Array(v.points.enumerated()), id: \.element.key) { i, pt in
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                Text("\(i + 1).").sType(SType(size: 17, weight: 700, line: 22, tracking: 0)).foregroundStyle(S.ink).frame(width: 30, alignment: .leading)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(pt.lead).sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 6)
                                        tag(pt.tag)
                                    }
                                    marked(pt.body).sType(SType(size: 16, weight: 400, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 14)
                            .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.horizontal, S.margin)
                if let lt = v.longTerm {
                    SCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Long term").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                Spacer()
                                tag("For your LEAPS")
                            }
                            marked(lt).sType(SType(size: 16, weight: 400, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, S.margin)
                }
            } else {
                // A name without the new content: the six points in the strategy's order on a solid card.
                SCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("What matters for your trade").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            .padding(.bottom, 4)
                        if let ins, !ins.points.isEmpty {
                            ForEach(Array(ins.points.enumerated()), id: \.offset) { i, pt in
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text("\(i + 1).").sType(SType(size: 16, weight: 600, line: 24, tracking: 0)).frame(width: 28, alignment: .leading)
                                    (Text(pt.lead + " ").font(SType(size: 16, weight: 600, line: 24, tracking: 0).font()) + marked(pt.body))
                                        .sType(SType(size: 16, weight: 400, line: 24, tracking: 0), tabular: false)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .foregroundStyle(S.ink)
                                .padding(.vertical, 12)
                                .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
                            }
                        } else {
                            Text("No read for \(n.t) yet.").sType(SType(size: 16, weight: 400, line: 24, tracking: 0), tabular: false).foregroundStyle(S.muted).padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal, S.margin)
            }
            VStack(spacing: 10) {
                Button { router.openCard(n.t, face: "todo") } label: {
                    Text("Go to To do" + (n.todoN > 0 ? " · \(PWords.n(n.todoN, "order"))" : "")).sType(SType(size: 17, weight: 600, line: 22, tracking: 0), tabular: false)
                        .foregroundStyle(S.paper).frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(S.ink)).contentShape(Capsule())
                }
                .buttonStyle(SPressStyle(scale: 0.97))
                button("Open Planner") { router.openGamma(n.t, view: nil, wall: nil) }
            }
            .padding(.horizontal, S.margin)
        }
    }

    /// The amber verdict card: a small label, the sentence, the chips.
    private func verdictCard<C: View>(label: String, text: String, @ViewBuilder chips: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.orangeDeep)
            Text(text).sType(SType(size: 20, weight: 700, line: 26, tracking: 0), tabular: false).foregroundStyle(S.ink)
                .fixedSize(horizontal: false, vertical: true)
            PWrap(spacing: 8) { chips() }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(S.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(S.orange.opacity(0.55), lineWidth: 1))
        .padding(.horizontal, S.margin)
    }

    /// A tinted pill: todo amber, good green, quiet grey.
    private func pill(_ t: String, tone: String) -> some View {
        let fg = tone == "todo" ? S.orangeDeep : tone == "good" ? S.green : S.muted
        let bg = tone == "todo" ? S.orange.opacity(0.18) : tone == "good" ? S.green.opacity(0.14) : S.track
        return Text(t).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(fg)
            .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(bg))
    }

    /// Helps green · Watch amber · Neutral grey · Hurts puts red; For your LEAPS grey.
    private func tag(_ t: String) -> some View {
        let fg = t == "Helps" ? S.green : t == "Watch" ? S.orangeDeep : t == "Hurts puts" ? S.red : S.muted
        let bg = t == "Helps" ? S.green.opacity(0.14) : t == "Watch" ? S.orange.opacity(0.18) : t == "Hurts puts" ? S.red.opacity(0.12) : S.track
        return Text(t).sType(SType(size: 12, weight: 600, line: 14, tracking: 0), tabular: false).foregroundStyle(fg)
            .padding(.horizontal, 8).frame(height: 22).background(Capsule().fill(bg)).fixedSize()
    }

    /// _Underscored_ words underlined.
    private func marked(_ s: String) -> Text {
        s.components(separatedBy: "_").enumerated().reduce(Text("")) { a, e in a + (e.offset % 2 == 1 ? Text(e.element).underline() : Text(e.element)) }
    }

    private func button(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity).frame(height: 44).background(Capsule().fill(S.track)).contentShape(Capsule())
        }
        .buttonStyle(SPressStyle(scale: 0.97))
    }

    // MARK: A watchlist name: one card

    private func watchCard(_ home: HomePayload, _ t: String) -> some View {
        let w = home.watchlist.first { $0.ticker == t }
        return SCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(t).sType(SType(size: 22, weight: 800, line: 28, tracking: -0.01), tabular: false).foregroundStyle(S.ink)
                    Spacer()
                    if let p = w?.price { Text("$\(PF.price(p))").sType(SType(size: 17, weight: 600, line: 22, tracking: 0)).foregroundStyle(S.ink) }
                    if let d = w?.ranges.d { Text(String(format: "%.1f%%", abs(d))).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(d >= 0 ? S.green : S.red) }
                }
                Text("Not in your book. Walls from open interest only, no tape labels.")
                    .sType(SType(size: 15, weight: 400, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    .fixedSize(horizontal: false, vertical: true)
                button("Open in Gamma") { router.openGamma(t, view: nil, wall: nil) }
            }
        }
        .padding(.horizontal, S.margin)
    }
}
