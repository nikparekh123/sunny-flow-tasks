//
//  SearchView.swift
//  Sunny
//
//  The Search page (handoff "Search for launch", block 27, SunnySearch with
//  nav="tab"): your last 10, suggestions while typing, voice with live
//  words, and the thread of text answers, each with Go deeper, Read aloud,
//  thumbs, Not what I asked and (under the last) two follow-ups.
//  The bottom: the tab you came from waits as one circle, the field beside
//  it. Opening folds the tab bar into that circle (288 to 62 in 0.5 s);
//  tapping the circle plays it back and returns to the tab.
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
    @State private var speaker = SXSpeaker()
    @State private var open = false
    @FocusState private var focused: Bool

    private var thread: Bool { !search.entries.isEmpty }
    private var typingNow: Bool { focused && !search.query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var showBack: Bool { thread || typingNow || voice.on }
    private var foldEase: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.5) }

    var body: some View {
        ZStack(alignment: .bottom) {
            SXBackground()
            page
                .opacity(open || reduce ? 1 : 0)
                .offset(y: open || reduce ? 0 : 18)
            fades
            topBar
            // The field sits 28 pt from the bottom of the screen (8 above the keyboard); the voice hint and the
            // microphone sheet 10 above the field.
            GeometryReader { g in
                let sb = g.safeAreaInsets.bottom, gap = sb > 60 ? 8 : 28 - sb
                VStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if voice.denied { micSheet.transition(.opacity.combined(with: .offset(y: 6))) }
                    else if voice.on { hint }
                    bottomBar
                }
                .frame(maxWidth: .infinity)
                .offset(y: -gap)
                .animation(.easeOut(duration: 0.2), value: voice.on)
                .animation(.easeOut(duration: 0.3), value: voice.denied)
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .onAppear {
            search.open()
            if reduce { open = true } else {
                withAnimation(.easeOut(duration: 0.3)) { open = true }
            }
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
                    if typingNow { suggestions }
                    else if thread { answers }
                    else { recents }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // From the top of the screen, as the design measures it (the status bar is inside it).
                .padding(.top, showBack ? 108 : 62)
                .padding(.bottom, 150)
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

    // MARK: Your last 10

    private var recents: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Search").sx(.title).foregroundStyle(SX.ink).accessibilityAddTraits(.isHeader).padding(.horizontal, 20)
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

    // MARK: Typing

    private var suggestions: some View {
        let s = search.suggestions()
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(s.rows) { row in
                Button { go(row.recent?.q ?? (row.a + row.b + row.c), cont: row.id == "ask" ? nil : false) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: row.recent == nil ? "magnifyingglass" : "clock")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(SX.muted).frame(width: 20)
                        (Text(row.a).fontWeight(.semibold) + Text(row.b).foregroundColor(SX.muted) + Text(row.c).fontWeight(.semibold))
                            .sx(.field).foregroundStyle(SX.ink).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                        if let r = row.recent { Text(when(r.at)).sx(.time).foregroundStyle(SX.muted) }
                    }
                    .padding(.vertical, 4)
                    .frame(minHeight: 52)
                    .overlay(alignment: .bottom) { Rectangle().fill(SX.line).frame(height: 1) }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            if s.noMatch {
                Text("Nothing you’ve asked matches yet. Sunny will still look.").sx(.small).foregroundStyle(SX.muted).padding(.top, 14)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: The thread

    private var answers: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(search.entries.enumerated()), id: \.element.id) { i, e in
                entry(e, last: i == search.entries.count - 1)
                    .padding(.top, i == 0 ? 0 : 20)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(SX.line).frame(height: 1) } }
                    .padding(.horizontal, 20)
                    .id(e.id)
            }
        }
    }

    @ViewBuilder private func entry(_ e: SearchStore.Entry, last: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(e.q).sx(.question).foregroundStyle(SX.muted)
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
                .frame(height: showBack ? 112 : 58)
            Spacer(minLength: 0)
            LinearGradient(stops: [.init(color: SX.fadeBottom, location: 0.4), .init(color: SX.fadeBottom.opacity(0), location: 1)], startPoint: .bottom, endPoint: .top)
                .frame(height: 120)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        VStack {
            HStack {
                if showBack {
                    Button(action: back) {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(SX.ink)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(thread || typingNow ? "Back to search" : "Back")
                    .transition(.opacity)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 54)
            Spacer()
        }
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeOut(duration: 0.2), value: showBack)
    }

    private func back() {
        if voice.on { voice.stop(); return }
        if typingNow || focused { search.query = ""; focused = false; return }
        if search.back() { return }
        close()
    }

    // MARK: The bottom

    @State private var folded = false

    private var bottomBar: some View {
        HStack(spacing: 8) {
            tabCircle
            field
        }
        .frame(width: 358)
        .onAppear {
            if reduce { folded = true; return }
            withAnimation(foldEase) { folded = true }
        }
    }

    /// The tab you came from, as one circle (folded from the whole tab bar when Search opens).
    private var tabCircle: some View {
        Button(action: close) {
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(HomeRouter.Tab.bar, id: \.self) { t in
                        VStack(spacing: 1) {
                            Image(systemName: t.icon).font(.system(size: 19, weight: .medium)).frame(height: 24)
                            Text(t.title).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(t == from ? SX.ink : SX.muted)
                        .frame(width: 70, height: 54)
                    }
                }
                .padding(.leading, 4)
                .opacity(folded ? 0 : 1)
                .animation(folded ? .easeOut(duration: 0.16) : .easeIn(duration: 0.24).delay(0.18), value: folded)
                Image(systemName: from.icon).font(.system(size: 19, weight: .medium)).foregroundStyle(SX.ink)
                    .frame(width: 62, height: 62)
                    .opacity(folded ? 1 : 0)
                    .animation(folded ? .easeOut(duration: 0.25).delay(0.22) : .easeIn(duration: 0.1), value: folded)
            }
            .frame(width: folded ? 62 : 288, height: 62, alignment: .leading)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Back to \(from.title)")
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(SX.muted)
                .opacity(folded ? 1 : 0)
                .animation(.easeOut(duration: 0.25).delay(folded ? 0.22 : 0), value: folded)
            Group {
                if voice.on {
                    Button { search.query = voice.stop(); focused = true } label: {
                        HStack(spacing: 8) {
                            SXWave()
                            Text(voice.words.isEmpty ? " " : voice.words).sx(.field).foregroundStyle(SX.ink).lineLimit(1).truncationMode(.head)
                            SXCaret()
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit what you said")
                } else {
                    TextField("", text: Binding(get: { search.query }, set: { search.query = $0 }),
                              prompt: Text(thread ? "Ask a follow-up" : "Ask about your book").foregroundStyle(SX.muted))
                        .sx(.field)
                        .foregroundStyle(SX.ink)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { send() }
                        .accessibilityLabel("Ask Sunny")
                }
            }
            .opacity(folded ? 1 : 0)
            .animation(.easeOut(duration: 0.25).delay(folded ? 0.24 : 0), value: folded)
            trailing
        }
        .padding(.leading, 20)
        .padding(.trailing, 6)
        .frame(height: 62)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .capsule)
    }

    @ViewBuilder private var trailing: some View {
        if voice.on {
            Button { voice.stop() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(SX.muted)
                    .frame(width: 40, height: 40).background(SX.fill, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop listening")
        } else if !search.query.trimmingCharacters(in: .whitespaces).isEmpty {
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundStyle(S.chipOnInk)
                    .frame(width: 40, height: 40).background(SX.ink, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask")
        } else {
            Button(action: listen) {
                Image(systemName: "mic.fill").font(.system(size: 17, weight: .medium)).foregroundStyle(SX.ink).frame(width: 40, height: 44)
            }
            .buttonStyle(.plain)
            .opacity(folded ? 1 : 0)
            .accessibilityLabel("Ask by voice")
        }
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

    private func close() {
        focused = false
        voice.stop()
        if reduce { leave(); return }
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.42)) { folded = false }
        withAnimation(.easeIn(duration: 0.22).delay(0.08)) { open = false }
        // The real tab bar takes over after 0.48 s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { leave() }
    }

    private var hint: some View {
        Text(voice.ending ? "Asking in a moment · tap the words to change them" : "Listening · tap the words to edit")
            .sx(.time.weighted(.semibold)).foregroundStyle(SX.ink)
            .padding(.horizontal, 14).frame(height: 30)
            .glassEffect(.regular, in: .capsule)
            .allowsHitTesting(false)
            .transition(.opacity)
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

/// The caret blinks once a second.
struct SXCaret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            Capsule().fill(SX.web).frame(width: 2, height: 22)
                .opacity(Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0)
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
