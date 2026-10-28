//
//  SearchView.swift
//  Sunny
//
//  The Search page (handoff "Search for launch", block 27, final: SunnySearch
//  with nav="tab" chat home="top", Oct 28): a page of its own over the tab you
//  came from. Recent, your last 10; a chat box the full width of the screen
//  that grows to five lines; each question a bubble on the right with its text
//  answer under it, Go deeper, Read aloud, thumbs, Not what I asked and (under
//  the last) two follow-ups. A back button top left, or a swipe from the left
//  edge, steps out one level at a time: the microphone sheet, voice, the
//  conversation, Recent, then the tab.
//

import SwiftUI

struct SunnySearchPage: View {
    let search: SearchStore
    let voice: SXVoice
    /// The tab Search was opened from, and going back to it.
    let from: HomeRouter.Tab
    let leave: () -> Void
    /// Bumped by a press and hold on the search button: open listening.
    let listenTick: Int

    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var dts
    @State private var speaker = SXSpeaker()
    /// Open: the page fades in (0.3 s) and rises 18 pt (0.5 s); the back button and the chat box follow from 0.24 s.
    @State private var shown = false
    @State private var risen = false
    @State private var chrome = false
    @FocusState private var focused: Bool

    private var thread: Bool { !search.entries.isEmpty }
    private var ease: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.5) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                SXBackground()
                page.offset(y: risen || reduce ? 0 : 18)
                fades
            }
            .opacity(shown ? 1 : 0)
            Group {
                topBar
                // The chat box sits 28 pt from the bottom of the screen (8 above the keyboard); the microphone
                // sheet 10 above it.
                GeometryReader { g in
                    let sb = g.safeAreaInsets.bottom, gap = sb > 60 ? 8 : 28 - sb
                    VStack(spacing: 10) {
                        Spacer(minLength: 0)
                        if voice.denied { micSheet.transition(.opacity.combined(with: .offset(y: 6))) }
                        chatBox.padding(.horizontal, max(8, (g.size.width - 358) / 2))
                    }
                    .frame(maxWidth: .infinity)
                    .offset(y: -gap)
                    .animation(.easeOut(duration: 0.3), value: voice.denied)
                }
            }
            .opacity(chrome ? 1 : 0)
            edge
        }
        .onAppear {
            search.open()
            if reduce { withAnimation(.easeOut(duration: 0.25)) { shown = true; risen = true; chrome = true }; return }
            withAnimation(.easeOut(duration: 0.3)) { shown = true }
            withAnimation(ease) { risen = true }
            withAnimation(.easeOut(duration: 0.25).delay(0.24)) { chrome = true }
        }
        .onChange(of: listenTick, initial: true) { _, t in
            guard t != search.listenSeen else { return }
            search.listenSeen = t
            listen()
        }
        .onChange(of: focused) { _, f in search.typing = f }
        .onDisappear { speaker.stop(); voice.stop() }
    }

    // MARK: Page

    private var page: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if thread { answers } else { recents }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // From the top of the screen, as the design measures it (the status bar is inside it).
                .padding(.top, 108)
                .padding(.bottom, 196)
                .id("top")
            }
            .ignoresSafeArea(.container, edges: .top)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: search.jumpTick) { _, _ in
                withAnimation(reduce ? nil : .easeOut(duration: 0.4)) {
                    if let j = search.jump { proxy.scrollTo(j, anchor: .top) } else { proxy.scrollTo("top", anchor: .top) }
                }
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // MARK: Recent, your last 10

    private var recents: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recent").sx(.title).foregroundStyle(SX.ink).accessibilityAddTraits(.isHeader).padding(.horizontal, 20)
            if search.recents.isEmpty && search.recentsLoaded { firstTime }
            ForEach(groups(), id: \.0) { g in
                VStack(alignment: .leading, spacing: 10) {
                    Text(g.0).sx(.group).foregroundStyle(SX.ink).accessibilityAddTraits(.isHeader)
                    ForEach(g.1) { r in recentCard(r) }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var firstTime: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask anything about your book. Your last 10 searches wait here, each with the answer it gave.")
                .sx(.say).foregroundStyle(SX.ink).fixedSize(horizontal: false, vertical: true)
            Text("Try asking").sx(.question).foregroundStyle(SX.muted).padding(.top, 6)
            SXFlow(spacing: 8) {
                ForEach(search.tries, id: \.self) { t in chip(t) { go(t, cont: false) } }
            }
        }
        .padding(.horizontal, 20)
    }

    private func recentCard(_ r: SXRecent) -> some View {
        Button { go(r.q, cont: false) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(r.q).sx(.question).foregroundStyle(SX.muted).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                    Text(when(r.at)).sx(.time).foregroundStyle(SX.muted)
                }
                if let big = r.preview?.big {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(big).sx(.recentBig).foregroundStyle(SX.tone(r.preview?.tone, SX.ink)).lineLimit(1).minimumScaleFactor(0.6)
                        if let l = r.preview?.line { Text(l).sx(.small.weighted(.medium)).foregroundStyle(SX.muted).multilineTextAlignment(.leading) }
                    }
                } else if let l = r.preview?.line, !l.isEmpty {
                    Text(l).sx(.recent).foregroundStyle(SX.ink).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SXPaper())
        }
        .buttonStyle(SPressStyle(scale: 0.985))
    }

    /// Today, Yesterday, Earlier, newest first (New York days).
    private func groups() -> [(String, [SXRecent])] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        var out: [(String, [SXRecent])] = []
        for r in search.recents {
            let g = cal.isDateInToday(r.at) ? "Today" : cal.isDateInYesterday(r.at) ? "Yesterday" : "Earlier"
            if let i = out.firstIndex(where: { $0.0 == g }) { out[i].1.append(r) } else { out.append((g, [r])) }
        }
        return out
    }

    /// 4:30 PM today and yesterday; the weekday this week; Oct 20 before that.
    private func when(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let f = DateFormatter(); f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US")
        if cal.isDateInToday(d) || cal.isDateInYesterday(d) { f.dateFormat = "h:mm a" }
        else if let days = cal.dateComponents([.day], from: d, to: .now).day, days < 6 { f.dateFormat = "EEE" }
        else { f.dateFormat = "MMM d" }
        return f.string(from: d)
    }

    // MARK: The conversation

    private var answers: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(search.entries.enumerated()), id: \.element.id) { i, e in
                entry(e, last: i == search.entries.count - 1)
                    .padding(.top, i == 0 ? 0 : 12)
                    .padding(.horizontal, 20)
                    .id(e.id)
            }
        }
    }

    @ViewBuilder private func entry(_ e: SearchStore.Entry, last: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            bubble(e.q)
            switch e.phase {
            case .loading: SXSkeleton()
            case .working(let step): SXWorking(step: step, since: e.bar)
            case .failed: EmptyView()
            case .done(let a):
                SXAnswerView(answer: a) { q in go(q, cont: true) }
                deeper(e)
                footer(e, a)
                if last && !a.followUps.isEmpty {
                    SXFlow(spacing: 8) { ForEach(a.followUps, id: \.self) { f in chip(f) { go(f, cont: true) } } }
                }
            }
        }
        .sxRise(0)
    }

    /// Your question, a bubble on the right (17 / 23, 500, on the fill color), at most 84% of the width.
    private func bubble(_ q: String) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 56)
            Text(q).sx(.row.weighted(.medium)).foregroundStyle(SX.ink).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10).padding(.horizontal, 16)
                .background(SX.fill, in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 6, topTrailingRadius: 22))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You asked: \(q)")
    }

    @ViewBuilder private func deeper(_ e: SearchStore.Entry) -> some View {
        if let d = e.deep {
            VStack(alignment: .leading, spacing: 12) {
                switch d {
                case .loading, .failed: SXWorking(step: "Reading more of your book", since: e.bar)
                case .working(let s): SXWorking(step: s, since: e.bar)
                case .done(let a):
                    Text("Deeper answer").sx(.time.weighted(.bold)).foregroundStyle(SX.muted)
                    SXAnswerView(answer: a) { q in go(q, cont: true) }
                }
            }
            .padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(SX.line).frame(height: 1) }
            .id(e.id.uuidString + "d")
            .sxRise(0)
        }
    }

    private func footer(_ e: SearchStore.Entry, _ a: SXAnswer) -> some View {
        let reading = speaker.reading == e.id
        let canDeep = e.deep == nil && !a.parts.contains { if case .none = $0 { return true }; return false }
        return HStack(spacing: 0) {
            if canDeep {
                Button { search.goDeeper(e.id) } label: {
                    Text("Go deeper").sx(.question).foregroundStyle(SX.ink).modifier(SXChip(height: 32)).padding(.horizontal, -2)
                        .frame(height: 44).contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Button { speaker.toggle(e.id, a.spoken) } label: {
                Image(systemName: reading ? "speaker.wave.2.fill" : "speaker.wave.2").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(reading ? SX.web : SX.muted).frame(width: 44, height: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reading ? "Stop reading" : "Read aloud")
            Spacer(minLength: 0)
            thumb(e, "up", "hand.thumbsup", "Good answer")
            thumb(e, "down", "hand.thumbsdown", "Bad answer")
            Button { search.notAsked(e.id) } label: {
                Text(e.notAsked ? "Saved for review" : "Not what I asked").sx(.time).foregroundStyle(SX.muted)
                    .padding(.leading, 6).padding(.trailing, 4).frame(height: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, -4)
    }

    private func thumb(_ e: SearchStore.Entry, _ v: String, _ icon: String, _ label: String) -> some View {
        let on = e.feedback == v
        return Button { search.thumb(e.id, v) } label: {
            Image(systemName: on ? icon + ".fill" : icon).font(.system(size: 15, weight: .medium))
                .foregroundStyle(on ? SX.ink : SX.muted).frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chip(_ t: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) { Text(t).sx(.small.weighted(.medium)).foregroundStyle(SX.ink).modifier(SXChip()) }
            .buttonStyle(SPressStyle())
    }

    // MARK: Furniture

    private var fades: some View {
        VStack(spacing: 0) {
            LinearGradient(stops: [.init(color: SX.fadeTop, location: 0.52), .init(color: SX.fadeTop.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: 112)
            Spacer(minLength: 0)
            LinearGradient(stops: [.init(color: SX.fadeBottom, location: 0.4), .init(color: SX.fadeBottom.opacity(0), location: 1)], startPoint: .bottom, endPoint: .top)
                .frame(height: 150)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// The back button top left: it names where it goes.
    private var topBar: some View {
        VStack {
            HStack {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(SX.ink)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(backLabel)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 54)
            Spacer()
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private var backLabel: String {
        voice.denied ? "Close" : thread ? "Back to Recent" : "Back to \(from.title)"
    }

    /// A swipe from the left edge (the first 18 pt, 60 pt to the right) steps back like the button.
    private var edge: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 18).contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 8).onEnded { v in if v.translation.width > 60 { back() } })
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
    }

    /// One level back: the microphone sheet, voice, the conversation (to Recent), then the tab.
    private func back() {
        if voice.denied { voice.denied = false; return }
        if voice.on { voice.stop(); return }
        if thread { focused = false; _ = search.back(); return }
        close()
    }

    // MARK: The chat box

    /// The full width of the screen: your words wrap and the box grows to five lines (110 pt), then scrolls
    /// inside. Mic when it is empty, send once there are words; Return adds a line.
    private var chatBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if voice.on {
                    Button { search.query = voice.stop(); focused = true } label: { heard.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit what you said")
                } else {
                    TextField("", text: Binding(get: { search.query }, set: { search.query = $0 }),
                              prompt: Text(thread ? "Ask a follow-up" : "Ask about your book").foregroundStyle(SX.muted), axis: .vertical)
                        .lineLimit(1...5)
                        .sx(.field)
                        .foregroundStyle(SX.ink)
                        .focused($focused)
                        .accessibilityLabel("Ask Sunny")
                }
            }
            .padding(.leading, 18).padding(.trailing, 13)
            HStack(spacing: 4) {
                if voice.on {
                    HStack(spacing: 8) {
                        SXWave()
                        Text(voice.ending ? "Asking in a moment" : "Listening · tap to edit").sx(.time.weighted(.semibold)).foregroundStyle(SX.muted)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    .allowsHitTesting(false)
                }
                Spacer(minLength: 0)
                trailing
            }
            .frame(minHeight: 44)
            .padding(.top, 4)
            .padding(.leading, 18)
        }
        .padding(.top, 14).padding(.trailing, 5).padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .animation(.easeOut(duration: 0.2), value: voice.on)
    }

    /// What has been heard, wrapping like typed text, the caret after it (blinks once a second).
    private var heard: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            let on = Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            (Text(voice.words) + Text(" |").foregroundColor(on ? SX.web : .clear))
                .sx(.field).foregroundStyle(SX.ink).lineLimit(5).truncationMode(.head)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var trailing: some View {
        if voice.on {
            Button { voice.stop() } label: { circle(SX.fill) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(SX.muted) } }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop listening")
        } else if !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button(action: send) { circle(SX.ink) { Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundStyle(S.chipOnInk) } }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask")
        } else {
            Button(action: listen) { circle(SX.ink) { Image(systemName: "mic.fill").font(.system(size: 16, weight: .medium)).foregroundStyle(S.chipOnInk) } }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask by voice")
        }
    }

    /// A 36 pt circle inside a 44 pt button.
    private func circle(_ fill: Color, @ViewBuilder _ icon: () -> some View) -> some View {
        icon().frame(width: 36, height: 36).background(fill, in: .circle).frame(width: 44, height: 44).contentShape(.rect)
    }

    /// Asks and puts the keyboard away.
    private func go(_ q: String, cont: Bool?) {
        focused = false
        search.ask(q, cont: cont)
    }

    private func send() {
        let q = search.query
        focused = false
        search.ask(q)
    }

    private func listen() {
        focused = false
        search.query = ""
        voice.start { q in search.ask(q) }
    }

    /// The same as opening, backwards: the page goes in 0.22 s after a 0.08 s wait, then the tab takes over.
    private func close() {
        focused = false
        voice.stop()
        speaker.stop()
        if reduce { withAnimation(.easeOut(duration: 0.25)) { shown = false; chrome = false } }
        else {
            withAnimation(.easeIn(duration: 0.22).delay(0.08)) { shown = false; chrome = false }
            withAnimation(.easeIn(duration: 0.3)) { risen = false }
        }
        leave()
    }

    private var micSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sunny can’t hear you").sx(.headline.weighted(.bold)).foregroundStyle(SX.ink)
                Text("Turn on the microphone for Sunny in Settings to ask by voice. You can still type.").sx(.small).foregroundStyle(SX.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { voice.openSettings() } label: {
                    Text("Open Settings").sx(.question).foregroundStyle(S.chipOnInk).frame(maxWidth: .infinity).frame(height: 44).background(SX.ink, in: .capsule)
                }
                Button { voice.denied = false } label: {
                    Text("Not now").sx(.question).foregroundStyle(SX.ink).frame(maxWidth: .infinity).frame(height: 44).background(SX.fill, in: .capsule)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Waiting

/// Sunny's own data: a short pulse of gray lines.
struct SXSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var dim = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bar(0.92, 24); bar(0.62, 24)
            bar(1, 14).padding(.top, 12); bar(1, 14); bar(0.46, 14)
        }
        .opacity(dim ? 0.45 : 1)
        .onAppear { if !reduce { withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dim = true } } }
        .accessibilityLabel("Loading")
    }
    private func bar(_ w: CGFloat, _ h: CGFloat) -> some View {
        GeometryReader { g in RoundedRectangle(cornerRadius: 6).fill(SX.fill).frame(width: g.size.width * w, height: h) }.frame(height: h)
    }
}

/// Live market data, research or the web: Working it out, the current step in words, and a bar.
struct SXWorking: View {
    let step: String
    let since: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var spin = false
    @State private var fill = 0.04

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().trim(from: 0, to: 0.25).stroke(SX.ink, style: .init(lineWidth: 2.5, lineCap: .round))
                    .background(Circle().stroke(SX.track, lineWidth: 2.5))
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                Text("Working it out").sx(.working).foregroundStyle(SX.ink)
            }
            Text(step).sx(.small).foregroundStyle(SX.muted).contentTransition(.opacity).animation(.easeOut(duration: 0.2), value: step)
                .accessibilityAddTraits(.updatesFrequently)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(SX.track)
                    Capsule().fill(SX.ink).frame(width: g.size.width * fill)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
        .onAppear {
            guard !reduce else { fill = 0.6; return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
            // Answers take a few seconds (up to 30 for big chains): the bar runs to 94% over about 8 s.
            withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 8)) { fill = 0.94 }
        }
    }
}

// MARK: - Voice marks

/// Five red bars, a 0.9 s wave, 0.12 s apart.
struct SXWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        TimelineView(.animation(paused: reduce)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let p = (t - Double(i) * 0.12).truncatingRemainder(dividingBy: 0.9) / 0.9
                    let k = reduce ? 0.7 : 0.3 + 0.7 * (0.5 - 0.5 * cos(p * 2 * .pi))
                    Capsule().fill(SX.down).frame(width: 3, height: 16).scaleEffect(y: k)
                }
            }
            .frame(height: 20)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Flow layout (chips wrap)

struct SXFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { y += row + spacing; x = 0; row = 0 }
            x += z.width + spacing; row = max(row, z.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, w), height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > b.minX && x + z.width > b.maxX { y += row + spacing; x = b.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}
