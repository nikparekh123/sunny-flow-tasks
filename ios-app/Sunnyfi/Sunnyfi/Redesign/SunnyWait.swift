//
//  SunnyWait.swift
//  Sunny — the two pieces of chrome that cover a wait.
//
//  Build sheets: `export 10/loading` — cards/pull-to-refresh.md and
//  cards/loading-screen.md. Neither is a card. Both are CHROME: the refresh
//  control is the pane's own, and the loading screen replaces a page while its
//  cards are not yet in.
//
//  ⚠ NOTHING SPINS ANYWHERE IN THE DECK. One hairline, one caret, one word; a
//  counter over a tape. The platform spinner is removed, not hidden.
//

import SwiftUI

// MARK: - what the wait is worth

/// ⚠ THE LOADING SCREEN NEEDS THETA BEFORE THETA HAS ARRIVED, which is the one
/// thing the sheet's `loadWaitContext()` hides: in the reference it is a second
/// cheap call, and here there is no second call — the figure it wants comes
/// from the very payload the screen is waiting for.
///
/// So the last good answer is kept. Every successful load writes the book's net
/// theta a day and the last close; the screen reads what was written. On a true
/// first run there is nothing, and the screen says so by printing no counter at
/// all rather than counting from a guess.
enum SunnyWait {
    private static let netKey = "sunnyfi.wait.thetaNet"
    private static let closeKey = "sunnyfi.wait.lastClose"

    static func remember(_ o: OptionsPayload) {
        if let w = o.theta?.weeks.last {
            UserDefaults.standard.set(w.net, forKey: netKey)
        }
        if let c = o.prices?.lastClose {
            UserDefaults.standard.set(c, forKey: closeKey)
        }
    }
    /// Net a day: what the short legs collect less what the long legs lose.
    static var thetaNetDay: Int? {
        UserDefaults.standard.object(forKey: netKey) as? Int
    }
    static var lastClose: String? {
        UserDefaults.standard.string(forKey: closeKey)
    }
    /// "Fri 11 Sep · 4:00 PM close". The time is not derived because it is not
    /// a variable: the US close is 4:00 PM ET by definition, so converting a
    /// stored instant would only invent a chance to get it wrong.
    static func closeLabel(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        let o = DateFormatter(); o.dateFormat = "EEE d MMM"
        return o.string(from: d) + " \u{00B7} 4:00 PM close"
    }
}

// MARK: - the loading screen

/// ⚠ THE WAIT IS PAID, AND THE FIGURE IS REAL. The counter is elapsed seconds ×
/// the book's net theta a day ÷ 86,400. Stop the clock at any moment and the
/// number is what the short legs collected in that time, net of what the long
/// legs lost. That is the whole wit of the screen and it only works because the
/// arithmetic is honest — it is not a progress bar wearing a costume.
///
/// ⚠ TIME IS THE ONLY THING THAT MOVES. A fixed caret, a scrolling ruler. No
/// spinner, no pulse, no rotating copy. Nothing accelerates and nothing
/// pretends to know how long is left.
///
/// ⚠ THERE IS NO DONE STATE. The page arriving IS done: the pane replaces the
/// screen. It never says "loaded", never turns green, never dismisses itself.
struct SunnyLoadingScreen: View {
    let title: String

    /* Kept from mount. A remount is a new wait; a re-render is not. */
    @State private var t0 = Date()
    @State private var now = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 8px a tenth, so the tape runs at 80px a second.
    private static let tenth: CGFloat = 8
    private static let length = 160          // 16 seconds of ruler
    private static let tapeH: CGFloat = 54

    private var elapsed: Double { max(0, now.timeIntervalSince(t0)) }
    private var netDay: Int? { SunnyWait.thetaNetDay }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(S.inter(S.t14, S.wBoldN))
                .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                .padding(.horizontal, 32)
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 18) {
                /* .2em, wider than the deck's .13em label, on purpose: it is
                   the one instrument-panel cue on the screen. */
                Text("EARNED WHILE YOU WAITED")
                    .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, 0.2))
                    .foregroundStyle(S.mute)
                if let d = netDay {
                    Text(String(format: "$%.4f", elapsed * Double(d) / 86_400))
                        .font(S.inter(64, S.wBoldN)).tracking(S.track(64, -0.04))
                        .foregroundStyle(S.gainText).sunnyLineBox(64)
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        readout("+" + optMoney(d), "a day")
                        readout(String(format: "%.1f s", elapsed), "this wait")
                    }
                } else {
                    /* ⚠ NO COUNTER RATHER THAN A GUESSED ONE. Before the first
                       successful load there is no rate to count, and a zero
                       here would be a measured nothing. */
                    Text("the book has not answered yet")
                        .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
                    readout(String(format: "%.1f s", elapsed), "this wait")
                }
            }
            .padding(.horizontal, 32)
            .monospacedDigit()

            Spacer().frame(height: 40)
            tape
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.vertical, 40)
        /* ⚠ --tile-ground, NOT --paper. The screen is a STATE, not a card: it
           sits where the pane sits and takes the tile grey so the cards' white
           reads as arrival when they land. */
        .background(S.tileGround)
        /* THE CLOCK. 100ms, and the tape glides between ticks on a linear
           transition of the same length, so the ruler is continuous. */
        .task(id: t0) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                now = Date()
            }
        }
    }

    private func readout(_ fig: String, _ word: String) -> Text {
        Text(fig).font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
            + Text(" " + word).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute)
    }

    /* ⚠ THE CARET NEVER MOVES; TIME DOES. A ruler of tenths scrolling left
       under a fixed mark is the only honest shape for a wait of unknown
       length — a bar that fills implies a destination the app cannot see. */
    private var tape: some View {
        ZStack {
            GeometryReader { g in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<Self.length, id: \.self) { i in
                        let major = i % 10 == 0
                        let medium = i % 5 == 0 && !major
                        VStack(spacing: 6) {
                            Rectangle().fill(major ? S.ink2 : S.hair)
                                .frame(width: 1, height: major ? 22 : medium ? 14 : 8)
                            /* 9px is under the deck's 11px floor and is
                               accepted here as a ruler graduation rather than
                               text: it is read against its tick, never alone. */
                            Text("\(i / 10) s")
                                .font(S.inter(9, S.wSemiN)).tracking(S.track(9, 0.04))
                                .foregroundStyle(S.mute)
                                .opacity(major ? 1 : 0).fixedSize()
                        }
                        .frame(width: Self.tenth, alignment: .top)
                    }
                }
                /* −(elapsed × 80) − 4: the half-tenth puts the caret on a tick
                   at t = 0. */
                .offset(x: g.size.width / 2 - elapsed * 10 * Self.tenth - Self.tenth / 2)
                .animation(reduceMotion ? nil : .linear(duration: 0.1), value: now)
            }
            Rectangle().fill(S.gainBar).frame(width: 2)
                .shadow(color: S.gainBar.opacity(0.45), radius: 6)
            /* The ruler runs on past both edges, so it fades into the ground
               rather than being cut by one. */
            LinearGradient(colors: [S.tileGround, .clear, .clear, S.tileGround],
                           startPoint: .leading, endPoint: .trailing)
                .allowsHitTesting(false)
        }
        .frame(height: Self.tapeH)
        .clipped()
        .measure("loading-screen")
    }
}

// MARK: - pull to refresh

/// ⚠ ONE LINE, ONE CARET, ONE WORD. NOTHING SPINS. The indicator is the deck's
/// hairline (a `--wash` track, 2pt), a 2 × 10 `--ink` caret — the same mark
/// Premium now uses for *usual* — and one 11pt word. No ring, no arrow, no
/// platform spinner. It is the quietest control on the page because refreshing
/// is the least interesting thing the page does.
///
/// ⚠ THE PULL IS THE LINE. The fill grows FROM THE CENTRE with the finger,
/// `--hair` until the threshold and `--ink` the moment it is armed, and the
/// caret appears at the same instant. The reader sees the arm before letting go.
///
/// ⚠ THE PANE HOLDS UNTIL THE FEED ANSWERS, capped at 8 seconds, and done shows
/// the ACTUAL close label rather than "updated". On a Sunday "Fri 11 Sep · 4:00
/// PM close" is honest in a way "just now" is not.
///
/// ⚠ AND IT IS DRIVEN BY SCROLL GEOMETRY, NOT A DRAG GESTURE — the one place
/// this departs from the sheet's pointer model, and it departs to be safer. The
/// pane is a vertical scroller inside a horizontal pager; a `DragGesture` here
/// would have to be reconciled against both. `onScrollGeometryChange` gives the
/// over-scroll distance the rubber band already computes, and
/// `onScrollPhaseChange` gives the release. The sheet's "gate pointer-down on
/// scrollTop === 0" then costs nothing: over-scroll only exists at the top.
private struct SunnyPullRefresh: ViewModifier {
    let action: () async -> Void

    private enum Phase { case idle, pull, fetch, done }
    @State private var phase: Phase = .idle
    @State private var pull: CGFloat = 0
    @State private var closeWord: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /* Damped pull that arms the release, and where the pane rests while the
       fetch runs. The scroller applies its own rubber band, so these are read
       against travel already damped once. */
    private static let threshold: CGFloat = 72
    private static let hold: CGFloat = 56
    private static let maxMs: UInt64 = 8_000

    private var progress: CGFloat { min(1, pull / Self.threshold) }
    private var armed: Bool { progress >= 1 }

    func body(content: Content) -> some View {
        content
            .contentMargins(.top, phase == .fetch || phase == .done ? Self.hold : 0,
                            for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { g in
                g.contentOffset.y + g.contentInsets.top
            } action: { _, y in
                guard phase == .idle || phase == .pull else { return }
                let p = max(0, -y)
                pull = min(115, p)
                if pull > 0 && phase == .idle { phase = .pull }
                if pull == 0 && phase == .pull { phase = .idle }
            }
            .onScrollPhaseChange { old, new in
                /* The release. Anything that is not the finger on the glass,
                   arriving from the finger on the glass. */
                guard old == .interacting, new != .interacting else { return }
                guard phase == .pull, armed else {
                    if phase == .pull { phase = .idle }
                    return
                }
                fire()
            }
            .overlay(alignment: .top) { indicator }
    }

    private func fire() {
        withAnimation(S.easeSettle(0.55)) { phase = .fetch }
        /* The travel is started explicitly rather than by a `value:` on the
           offset: a repeating animation keyed to a derived value restarts every
           time the view re-evaluates, and the caret stutters. */
        caretSwing = false
        if !reduceMotion {
            DispatchQueue.main.async {
                withAnimation(S.easeSettle(1.2).repeatForever(autoreverses: true)) {
                    caretSwing = true
                }
            }
        }
        Task {
            /* The pane holds for the real answer, never a fixed-length fake —
               but it is capped, because a feed that never answers must not
               leave the control open for ever. */
            await withTaskGroup(of: Void.self) { g in
                g.addTask { await action() }
                g.addTask { try? await Task.sleep(for: .milliseconds(Self.maxMs)) }
                await g.next()
                g.cancelAll()
            }
            closeWord = SunnyWait.lastClose.map(SunnyWait.closeLabel)
            withAnimation(.easeOut(duration: 0.3)) { phase = .done }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { caretSwing = false }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(S.easeSettle(0.55)) { phase = .idle; pull = 0 }
        }
    }

    /* The zone is exactly as tall as the pull, so the line is parked just above
       the pane's top edge at every distance. */
    private var zoneH: CGFloat {
        switch phase {
        case .idle: return 0
        case .pull: return pull
        case .fetch, .done: return Self.hold
        }
    }

    @ViewBuilder private var indicator: some View {
        if zoneH > 0 {
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                Text(word)
                    .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                    .monospacedDigit().lineLimit(1).fixedSize()
                ZStack(alignment: .leading) {
                    GeometryReader { g in
                        ZStack(alignment: .center) {
                            Capsule().fill(S.wash).frame(height: 2)
                            Capsule().fill(lineInk)
                                .frame(width: g.size.width * fillFrac, height: 2)
                                .animation(.linear(duration: 0.12), value: fillFrac)
                                .animation(.easeOut(duration: 0.3), value: lineInk)
                        }
                        .frame(maxHeight: .infinity)
                        /* The caret: at the centre the moment it arms, then it
                           travels the line while the feed answers. An ease, not
                           a linear sweep, so it reads as a scan rather than a
                           metronome. */
                        if caretShown {
                            Rectangle().fill(S.ink)
                                .frame(width: 2, height: 10)
                                .offset(x: g.size.width * caretAt - 1)
                                .transition(.opacity)
                        }
                    }
                }
                .frame(height: 10)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
            }
            .padding(.bottom, 14)
            .frame(height: zoneH, alignment: .bottom)
            .frame(maxWidth: .infinity)
            .clipped()
            .allowsHitTesting(false)
            .measure("pull-refresh")
        }
    }

    /* Four strings, one at a time, never two at once. */
    private var word: String {
        switch phase {
        case .fetch: return "asking the market\u{2026}"
        case .done: return closeWord ?? "up to date"
        default: return armed ? "let go" : "pull for the latest"
        }
    }
    private var fillFrac: CGFloat {
        switch phase {
        case .idle: return 0
        case .pull: return progress
        case .fetch, .done: return 1
        }
    }
    /* Green appears once, for .65 s, and only when the feed actually answered. */
    private var lineInk: Color {
        phase == .done ? S.gainBar : (armed || phase == .fetch ? S.ink : S.hair)
    }
    private var caretShown: Bool { (phase == .pull && armed) || phase == .fetch }
    @State private var caretSwing = false
    private var caretAt: CGFloat {
        phase == .fetch ? (caretSwing ? 1 : 0) : 0.5
    }
}

extension View {
    /// Replaces `.refreshable` — the platform spinner is removed, not hidden.
    func sunnyPullRefresh(_ action: @escaping () async -> Void) -> some View {
        modifier(SunnyPullRefresh(action: action))
    }
}

// MARK: - the 400ms gate

/// ⚠ NOTHING FOR THE FIRST 400 MILLISECONDS. A flash of the loading screen on a
/// fast load is worse than a blank pane — it reads as the app stumbling. Below
/// the gate the slot stays empty; above it the screen appears and stays until
/// the page renders.
struct SunnyWaitGate: View {
    let title: String
    @State private var show = false

    var body: some View {
        Group {
            if show {
                SunnyLoadingScreen(title: title)
                    .frame(height: 520)
                    .clipShape(RoundedRectangle(cornerRadius: S.radiusCard,
                                                style: .continuous))
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            show = true
        }
    }
}
