//
//  SunnyAftershock.swift
//  Sunny
//
//  Blocks 26 and 03b (handoff 26) · Aftershock, the crash scanner. One
//  component, two views, the full page and the Home deck card, on one scanner
//  model and one clock (SunnyAftershock.dc.html). After every close
//  crash-scan reads the universe (516 names) for a one-day drop of 15% or
//  more; the orbit draws one dot per name in a single Canvas pass.
//
//  Day 2 (Nik, 19 Oct 2026, Option 1): a crash's Day 2 move is only known at
//  the Day 2 close, so through Day 2 its row shows Day 1 ticked and Day 2
//  "today"; the next scan ticks it with the move, under that day's new
//  crashes, until the next countdown. No trade instructions anywhere.
//

import SwiftUI
import QuartzCore

// MARK: - The scanner at a moment

struct AftershockScan {
    enum Mode: Equatable { case wait, soon, scan, done, none }

    struct Row: Identifiable, Equatable {
        let e: Aftershock.Event
        /// Day 2's close is in (both ticks and the move).
        let settled: Bool
        /// When Day 2 closes, until it has: "today", "tomorrow", "Monday".
        let when: String
        var id: String { e.id }
    }

    let mode: Mode
    let universe: Int
    /// Seconds to 4:15 PM in the countdown, and since 4:15 PM in the scan.
    let rem: Double
    let sinceScan: Double
    /// The newest crashes, biggest drop first: on the floor under the orbit
    /// and first in the card.
    let top: [Row]
    /// The crashes whose Day 2 just closed, under them.
    let settled: [Row]
    /// Waiting: "4:15 PM" today, else "Mon 4:15 PM". No crashes: "tomorrow"
    /// or "Monday".
    let nextScan: String
    let nextDay: String
    /// The card's cycle, 4:00 PM to the next 4:00 PM (its ✕ key).
    let cycle: String
    /// The deck shows the card now (03b, When it shows).
    let card: Bool

    static let countdownAt: Double = 16 * 3600, scanAt: Double = 16 * 3600 + 900
    static let longDays = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    static func at(_ now: Date, _ a: Aftershock, calendar cal: [CalendarDay]) -> AftershockScan {
        let t = MarketClock.ny(now), s = secondsNY(now), today = t.date
        let trading = MarketClock.isTradingDay(today, weekday: t.weekday, cal)
        let evening = trading && s >= countdownAt
        let fresh = a.events.filter { $0.day == today }
        let scannedToday = a.scans.contains { $0.day == today }

        let mode: Mode
        if evening {
            mode = scannedToday ? (fresh.isEmpty ? .none : .done) : s < scanAt ? .soon : .scan
        } else {
            mode = .wait
        }

        let tomorrow = MarketClock.addDays(today, 1).iso
        let word: (String?) -> String = { d in
            guard let d else { return "tomorrow" }
            if d == today { return "today" }
            if d == tomorrow { return "tomorrow" }
            return longDays[MarketClock.addDays(d, 0).weekday]
        }
        let row: (Aftershock.Event) -> Row = { e in
            Row(e: e, settled: e.day2Pct != nil, when: word(e.day2))
        }
        // The last scan before today (the calendar only carries closures to
        // come, so past trading days come from the scans).
        let last = a.scans.map(\.day).filter { $0 < today }.max()
        var top: [Row] = [], settled: [Row] = []
        switch mode {
        case .done, .none:
            top = fresh.map(row)
            settled = a.events.filter { $0.day2 == today && $0.day2Pct != nil }.map(row)
        case .wait:
            if let l = last {
                top = a.events.filter { $0.day == l && $0.day2Close == nil }.map(row)
                settled = a.events.filter { $0.day2 == l && $0.day2Pct != nil }.map(row)
            }
        case .soon, .scan:
            break
        }

        let next = MarketClock.nextTrading(after: today, cal)
        let nextScan = trading && s < countdownAt ? "4:15 PM" : "\(MarketClock.dayName[next.weekday]) 4:15 PM"
        let nextDay = next.iso == tomorrow ? "tomorrow" : longDays[next.weekday]

        let card: Bool
        if !trading { card = false }
        else if !evening { card = !top.isEmpty }
        else {
            switch mode {
            case .done: card = true
            case .none: card = s < 20 * 3600
            default: card = s < 20 * 3600   // the bars never came: gone at 8 PM
            }
        }
        return AftershockScan(mode: mode, universe: a.universe,
                              rem: max(0, scanAt - s), sinceScan: max(0, s - scanAt),
                              top: top, settled: settled, nextScan: nextScan, nextDay: nextDay,
                              cycle: evening ? today : (last ?? today), card: card)
    }

    private static let nyCal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = MarketClock.ny; return c }()
    /// Seconds since midnight in New York.
    static func secondsNY(_ d: Date) -> Double {
        let c = nyCal.dateComponents([.hour, .minute, .second, .nanosecond], from: d)
        return Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)) + Double(c.nanosecond ?? 0) / 1e9
    }

    // MARK: The frame

    /// What the orbit and the words show this instant. A scan that lands
    /// while it is watched plays one sonar pass (`reveal`), each crash
    /// leaving its orbit as the wave reaches it, then settles into results.
    func frame(_ now: Date, reveal: Date?, pending: Bool, reduce: Bool) -> AftershockFrame {
        let n = Double(universe)
        switch mode {
        case .wait: return AftershockFrame(mode: .wait)
        case .soon: return AftershockFrame(mode: .soon, rem: rem)
        case .scan:
            // Waiting for the session's bars: the wave keeps reading.
            let sl = sinceScan.truncatingRemainder(dividingBy: 9.5), p = min(1, sl / 7)
            return AftershockFrame(mode: .scan, p: p, hold: min(1, max(0, sl - 7)), count: Int((p * n).rounded()))
        case .done, .none:
            let lt: Double? = pending ? 0 : reveal.map { now.timeIntervalSince($0) }
            if let lt, lt < 8, !reduce {
                let p = min(1, lt / 7)
                let found = top.filter { OrbitGeo.shared(universe).hit($0.e.ticker, among: top.map(\.e.ticker)) <= p }.count
                return AftershockFrame(mode: .scan, p: p, hold: min(1, max(0, lt - 7)), found: found, count: Int((p * n).rounded()))
            }
            return AftershockFrame(mode: mode, p: 1, found: top.count, count: universe)
        }
    }
}

struct AftershockFrame {
    var mode: AftershockScan.Mode
    /// The sonar's reach (0 to 1) and its fade once it is at the edge.
    var p: Double = 0
    var hold: Double = 0
    var rem: Double = 0
    /// Crashes found so far, names read so far.
    var found = 0
    var count = 0

    /// The countdown's and the scan's progress, for the ring and the bar.
    var progress: Double { mode == .soon ? 1 - rem / 900 : mode == .scan ? p : 0 }
    var barOn: Bool { (mode == .soon || mode == .scan) && hold < 1 }
    var clock: String {
        let r = Int(rem)
        return "\(r / 60):" + String(format: "%02d", r % 60)
    }
}

// MARK: - Orbit geometry

/// 516 names on seven rings: radii 34 + 17.5 k, names shared by
/// circumference, inner rings faster, directions alternating.
final class OrbitGeo {
    let n: Int
    let k: [Int], r: [Double], b: [Double], w: [Double]

    private init(_ n: Int) {
        self.n = n
        let rk = (0..<7).map { 34 + Double($0) * 17.5 }
        var ns = rk.map { Int((Double(n) * $0 / 605.5).rounded()) }
        ns[6] += n - ns.reduce(0, +)
        var k: [Int] = [], r: [Double] = [], b: [Double] = [], w: [Double] = []
        for (kk, rr) in rk.enumerated() where ns[kk] > 0 {
            for j in 0..<ns[kk] {
                k.append(kk); r.append(rr)
                b.append(Double(j) / Double(ns[kk]) * 2 * .pi + Double(kk) * 0.7)
                w.append((kk % 2 == 1 ? -1 : 1) * 0.32 / (1 + Double(kk) * 0.45))
            }
        }
        self.k = k; self.r = r; self.b = b; self.w = w
    }

    nonisolated(unsafe) private static var cache: OrbitGeo?
    static func shared(_ n: Int) -> OrbitGeo {
        if let c = cache, c.n == n { return c }
        let g = OrbitGeo(max(1, n)); cache = g; return g
    }

    /// Each crashed name's dot: a fixed place per ticker, never shared.
    func slots(_ tickers: [String]) -> [Int] {
        var used = Set<Int>(), out: [Int] = []
        for t in tickers {
            var h: UInt32 = 2166136261
            for c in t.utf8 { h = (h ^ UInt32(c)) &* 16777619 }
            var i = Int(h % UInt32(n))
            while used.contains(i) { i = (i + 1) % n }
            used.insert(i); out.append(i)
        }
        return out
    }
    /// The share of the sonar's reach at which a name is read.
    func hit(_ ticker: String, among all: [String]) -> Double {
        guard let j = all.firstIndex(of: ticker) else { return 1 }
        return r[slots(all)[j]] / 159
    }

    /// Where the j-th of m crashes lands on the floor under the orbit: two sit
    /// at 128 and 224 as the design does, four to a row, rows stacking up.
    static func floor(_ j: Int, _ m: Int) -> CGPoint {
        let row = j / 4, inRow = min(4, m - row * 4), i = j % 4
        let gap: Double = m <= 3 ? 96 : 80
        return CGPoint(x: 176 + (Double(i) - Double(inRow - 1) / 2) * gap, y: 326 - 22 * Double(row))
    }
}

/// What carries from frame to frame: the orbit's turn (it slows into 4:15)
/// and where each crash left its orbit.
final class OrbitMotion {
    var T = 0.0
    var last: Double?
    var falls: [String: (x: Double, y: Double, t: Double)] = [:]
    #if DEBUG
    /// `-preset as.perf=1`: logs the orbit's draw time every 240 frames.
    private var cost: [Double] = []
    func perf(_ s: Double) {
        guard DebugPreset.bool("as.perf") else { return }
        cost.append(s * 1000)
        guard cost.count == 240 else { return }
        let sorted = cost.sorted()
        print(String(format: "[orbit] draw ms mean %.2f p95 %.2f max %.2f", cost.reduce(0, +) / 240, sorted[227], sorted[239]))
        cost = []
    }
    #endif
}

// MARK: - The orbit, one Canvas pass

enum AftershockOrbit {
    static let label = SType(size: 11, weight: 700, line: 11, tracking: 0)

    /// Draws in the page's 353 × 340 space (center 176.5, 158); the caller
    /// scales it for the card.
    static func draw(_ g: GraphicsContext, fr: AftershockFrame, crashes: [String], universe: Int,
                     motion: OrbitMotion, clock t0: Double, reduce: Bool,
                     ink: Color, red: Color, k: Double, labels: Bool) {
        let geo = OrbitGeo.shared(universe), tau2 = 2 * Double.pi
        let t = reduce ? 0 : t0
        let dt = motion.last.map { min(0.1, max(0, t0 - $0)) } ?? 0
        motion.last = t0
        if !reduce {
            let speed = fr.mode == .soon ? 0.15 + 0.85 * fr.rem / 900 : fr.mode == .scan ? 0.5 : 1
            motion.T += dt * speed
        }
        let T = motion.T
        if fr.mode != .scan { motion.falls = [:] }

        let cx = 176.5, cy = 158.0, rw = fr.p * 159
        let circle = { (x: Double, y: Double, rr: Double) in Path(ellipseIn: CGRect(x: x - rr, y: y - rr, width: 2 * rr, height: 2 * rr)) }

        // Rings
        for kk in 0..<7 {
            let rr = 34 + Double(kk) * 17.5
            let a = fr.mode == .scan ? (rr <= rw ? 0.14 : 0.05) : fr.mode == .soon ? 0.1 : 0.06
            g.stroke(circle(cx, cy, rr), with: .color(ink.opacity(a * k)), lineWidth: 1)
        }
        // Countdown ring: fills clockwise from 12 o'clock, a 3 pt head
        if fr.mode == .soon {
            let f = fr.progress, h0 = -Double.pi / 2, ha = h0 + f * tau2
            g.stroke(circle(cx, cy, 153), with: .color(ink.opacity(0.1 * k)), lineWidth: 1.5)
            if f > 0 {
                var arc = Path()
                arc.addArc(center: CGPoint(x: cx, y: cy), radius: 153, startAngle: .radians(h0), endAngle: .radians(ha), clockwise: false)
                g.stroke(arc, with: .color(ink.opacity(0.8 * k)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                g.fill(circle(cx + 153 * cos(ha), cy + 153 * sin(ha), 3), with: .color(ink.opacity(k)))
            }
        }
        // Sonar
        if fr.mode == .scan, fr.hold < 1, rw > 2 {
            let disc = circle(cx, cy, rw)
            g.fill(disc, with: .radialGradient(Gradient(stops: [
                .init(color: ink.opacity(0), location: 0),
                .init(color: ink.opacity(0.09 * (1 - fr.hold) * k), location: 1),
            ]), center: CGPoint(x: cx, y: cy), startRadius: max(0, rw - 34), endRadius: rw))
            g.stroke(disc, with: .color(ink.opacity(0.6 * (1 - fr.hold) * k)), lineWidth: 1.5)
        }
        // The center breathes
        if fr.mode == .wait || fr.mode == .soon {
            let b = 0.5 + 0.5 * sin(t * (fr.mode == .soon ? 3 : 1.2))
            g.fill(circle(cx, cy, 2.5 + b), with: .color(ink.opacity((0.5 + 0.4 * b) * k)))
        }

        // The names, batched by opacity (41 steps)
        let slots = geo.slots(crashes)
        let hits = slots.map { geo.r[$0] / 159 }
        let out: (Int) -> Bool = { j in
            switch fr.mode {
            case .wait, .done: true
            case .scan: hits[j] <= fr.p
            default: false
            }
        }
        var gone = Set<Int>()
        for (j, s) in slots.enumerated() where out(j) { gone.insert(s) }
        var batch = [Path](repeating: Path(), count: 41)
        for i in 0..<geo.n where !gone.contains(i) {
            let an = geo.b[i] + geo.w[i] * T, rr = geo.r[i]
            let x = cx + rr * sin(an), y = cy - rr * cos(an)
            var a: Double, s: Double
            switch fr.mode {
            case .wait, .soon:
                let ph = fr.mode == .wait ? t * 1.2 - Double(geo.k[i]) * 0.8 : t * 2 + Double(geo.k[i]) * 0.8
                let w = pow(max(0, sin(ph)), 6)
                a = 0.14 + 0.5 * w; s = 1.3 + 0.8 * w
            case .scan:
                if rr <= rw { let d = rw - rr; a = 0.3 + 0.6 * exp(-d / 16); s = 1.4 + 0.9 * exp(-d / 10) }
                else { a = 0.08; s = 1.2 }
            default:
                a = 0.1; s = 1.3
            }
            let q = max(0, min(40, Int((a * k * 40).rounded())))
            batch[q].addEllipse(in: CGRect(x: x - s, y: y - s, width: 2 * s, height: 2 * s))
        }
        for (q, p) in batch.enumerated() where !p.isEmpty {
            g.fill(p, with: .color(ink.opacity(Double(q) / 40)))
        }

        // Crashes: out of orbit, down to the floor, a slow ring
        for (j, tk) in crashes.enumerated() where out(j) {
            let fl = OrbitGeo.floor(j, crashes.count)
            var x = fl.x, y = fl.y
            var q = ((t + Double(j) * 1.1).truncatingRemainder(dividingBy: 2.4)) / 2.4
            if fr.mode == .scan {
                let i = slots[j]
                if motion.falls[tk] == nil {
                    let an = geo.b[i] + geo.w[i] * T
                    motion.falls[tk] = (cx + geo.r[i] * sin(an), cy - geo.r[i] * cos(an), t0)
                }
                let h = motion.falls[tk]!
                let tau = reduce ? 1 : min(1, (t0 - h.t) / 1.1)
                x = h.x + (fl.x - h.x) * (1 - (1 - tau) * (1 - tau))
                y = h.y + (fl.y - h.y) * tau * tau
                if tau < 1 {
                    q = tau
                    var trail = Path(); trail.move(to: CGPoint(x: h.x, y: h.y)); trail.addLine(to: CGPoint(x: x, y: y))
                    g.stroke(trail, with: .color(red.opacity(0.35 * (1 - tau))), lineWidth: 1)
                }
            }
            g.stroke(circle(x, y, 4 + q * 20), with: .color(red.opacity(0.6 * (1 - q))), lineWidth: 1.5)
            g.fill(circle(x, y, 8), with: .color(red.opacity(0.18)))
            g.fill(circle(x, y, 3.4), with: .color(red))
            if labels {
                g.draw(Text(tk).font(label.font()).foregroundColor(red), at: CGPoint(x: x + 9, y: y), anchor: .leading)
            }
        }
    }
}

// MARK: - The page (block 26)

struct SunnyAftershockPage: View {
    let home: HomePayload
    let onBack: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme
    @State private var motion = OrbitMotion()
    /// When a scan landed on screen, and the mode last seen (so the frame the
    /// results arrive on already starts the pass, never flashes the rows).
    @State private var reveal: Date?
    @State private var seen: AftershockScan.Mode?

    static let big = SType(size: 34, weight: 800, line: 34, tracking: -0.02)
    static let line15 = SType(size: 15, weight: 500, line: 20, tracking: 0)
    static let label15 = SType(size: 15, weight: 600, line: 20, tracking: 0)
    static let title20 = SType(size: 20, weight: 700, line: 24, tracking: 0)
    static let small13 = SType(size: 13, weight: 500, line: 16, tracking: 0)
    static let clockFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = MarketClock.ny
        f.dateFormat = "h:mm a"; return f
    }()

    private var data: Aftershock { home.aftershock ?? Aftershock(universe: 516, scans: [], events: [], nextScanDay: nil) }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    orbit.padding(.top, 12)
                    Spacer(minLength: 20)
                    card
                }
                .padding(.top, 20).padding(.horizontal, S.margin)
                .padding(.bottom, 32)   // 32 from the screen's edge (block 26)
                .frame(minHeight: geo.size.height + geo.safeAreaInsets.bottom)
                .foregroundStyle(S.ink)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(S.screen.ignoresSafeArea())
        // Back from the left edge, as the Planner does.
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.startLocation.x < 30, v.translation.width > 80, abs(v.translation.height) < 60 { onBack() }
        })
        .onAppear {
            seen = AftershockScan.at(SClock.now(), data, calendar: home.calendar).mode
            #if DEBUG && targetEnvironment(simulator)
            if DebugPreset.bool("as.reveal") { reveal = SClock.now() }
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Path { p in p.move(to: CGPoint(x: 9.5, y: 2.5)); p.addLine(to: CGPoint(x: 2.5, y: 10)); p.addLine(to: CGPoint(x: 9.5, y: 17.5)) }
                    .stroke(S.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 12, height: 20)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(SPressStyle(scale: 0.94))
            .accessibilityLabel("Back")
            Text("Aftershock").sType(Self.title20, tabular: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(Self.clockFmt.string(from: SClock.now())).sType(Self.line15).foregroundStyle(S.muted)
            }
        }
        .frame(height: 44)
    }

    private var orbit: some View {
        TimelineView(.animation) { ctx in
            let now = SClock.now()
            let m = AftershockScan.at(now, data, calendar: home.calendar)
            let fr = m.frame(now, reveal: reveal, pending: pending(m), reduce: reduce)
            let dark = scheme == .dark
            Canvas { g, _ in
                #if DEBUG
                let t0 = CACurrentMediaTime()
                #endif
                AftershockOrbit.draw(g, fr: fr, crashes: m.top.map(\.e.ticker), universe: m.universe,
                                     motion: motion, clock: ctx.date.timeIntervalSinceReferenceDate, reduce: reduce,
                                     ink: S.ink, red: S.red, k: dark ? 1 : 0.9, labels: true)
                #if DEBUG
                motion.perf(CACurrentMediaTime() - t0)
                #endif
            }
        }
        .frame(width: 353, height: 340)
        .accessibilityHidden(true)
    }

    /// Results arrived on this very frame, before `reveal` is set.
    private func pending(_ m: AftershockScan) -> Bool {
        reveal == nil && seen == .scan && (m.mode == .done || m.mode == .none) && !reduce
    }

    // MARK: The glass card

    private var card: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { _ in
            let now = SClock.now()
            let m = AftershockScan.at(now, data, calendar: home.calendar)
            let fr = m.frame(now, reveal: reveal, pending: pending(m), reduce: reduce)
            VStack(alignment: .leading, spacing: 0) {
                status(m, fr)
                ForEach(Array(m.top.enumerated()), id: \.element.id) { j, r in
                    AftershockRow(row: r, open: fr.mode != .scan || fr.found > j, settledShown: r.settled)
                }
                ForEach(m.settled) { r in
                    AftershockRow(row: r, open: true, settledShown: true)
                }
            }
            .padding(.top, 20).padding(.horizontal, 20).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: S.rDeck))
            .shadow(color: .black.opacity(scheme == .dark ? 0.2 : 0.04), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.10), radius: 12, y: 10)
            .onChange(of: m.mode) { old, new in
                seen = new
                if old == .scan, new == .done || new == .none, !reduce { reveal = now }
            }
        }
    }

    private func status(_ m: AftershockScan, _ fr: AftershockFrame) -> some View {
        let words = Self.words(m, fr)
        return VStack(alignment: .leading, spacing: 6) {
            Text(words.0).sType(Self.label15, tabular: false).foregroundStyle(S.muted)
            // The countdown rolls; the scan's count runs too fast to roll
            // (a roll every 0.1 s never settles), so it is set as it reads.
            Text(words.1).sType(Self.big)
                .lineLimit(1).fixedSize()
                .contentTransition(fr.mode == .scan ? .identity : .numericText())
                .animation(reduce || fr.mode == .scan ? nil : S.standard(S.roll), value: words.1)
            Text(words.2).sType(Self.line15).foregroundStyle(S.muted)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.3), value: words.2)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(S.track)
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: 2).fill(S.ink).frame(width: g.size.width * fr.progress)
                }
            }
            .frame(height: 3)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .padding(.top, 8)
            .opacity(fr.barOn ? 1 : 0)
            .animation(.easeOut(duration: 0.5), value: fr.barOn)
            .accessibilityHidden(true)
        }
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
    }

    /// Label, big line and sub line for each state (block 26, Scenarios).
    static func words(_ m: AftershockScan, _ fr: AftershockFrame) -> (String, String, String) {
        let u = m.universe
        switch fr.mode {
        case .wait: return ("Next scan", m.nextScan, "Checks \(u) names after the close")
        case .soon: return ("Scan in", fr.clock, "at 4:15 PM")
        case .scan:
            let so = fr.found == 0 ? "Looking for drops of 15% or more" : "\(fr.found) crash\(fr.found == 1 ? "" : "es") so far"
            return ("Scanning", "\(fr.count) of \(u)", so)
        case .done:
            return ("Today", "\(m.top.count) crash\(m.top.count == 1 ? "" : "es")", "\(u) names checked")
        case .none: return ("Today", "No crashes", "Next scan \(m.nextDay) 4:15 PM")
        }
    }
}

/// One crash: ticker, the prior close to the crash close, the drop; then the
/// Day 1 and Day 2 ticks. No company names, no instructions.
struct AftershockRow: View {
    let row: AftershockScan.Row
    let open: Bool
    let settledShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let e = row.e, settled = settledShown && row.settled
        // The 1 pt rule sits above the row's 14 pt padding, as the design's
        // border-top does (a row is 73 pt: 1 + 14 + 24 + 4 + 16 + 14).
        VStack(alignment: .leading, spacing: 0) {
        Rectangle().fill(S.pRule).frame(height: 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(e.ticker).sType(SunnyAftershockPage.title20, tabular: false)
                    Text("\(F.money(e.prevClose, cents: true)) → \(F.money(e.close, cents: true))")
                        .sType(SunnyAftershockPage.line15).foregroundStyle(S.muted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Text(F.pct(e.dropPct, places: 1)).sType(SunnyAftershockPage.title20).foregroundStyle(S.red)
            }
            HStack(spacing: 16) {
                HStack(spacing: 6) { DayTick(on: true); Text("Day 1") }
                HStack(spacing: 6) { DayTick(on: settled); day2(settled) }
            }
            .sType(SunnyAftershockPage.small13)
            .foregroundStyle(S.muted)
            .lineLimit(1)
        }
        .padding(.vertical, open ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: open ? nil : 0, alignment: .top)
        .clipped()
        }
        .opacity(open ? 1 : 0)
        .animation(reduce ? nil : S.standard(0.6), value: open)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y(settled))
        .accessibilityHidden(!open)
    }

    private func day2(_ settled: Bool) -> Text {
        let f = SunnyAftershockPage.small13
        guard settled, let p = row.e.day2Pct else {
            return Text("Day 2 ").font(f.font()) + Text(row.when).font(f.font())
        }
        let move = p > 0 ? "up \(F.pct(p, places: 1))" : p < 0 ? "down \(F.pct(p, places: 1))" : "flat"
        return Text("Day 2 ").font(f.font())
            + Text(move).font(f.weighted(600).font(tabular: true)).foregroundStyle(p > 0 ? S.green : p < 0 ? S.red : S.muted)
    }

    private func a11y(_ settled: Bool) -> String {
        let e = row.e
        var s = "\(e.ticker), down \(F.pct(e.dropPct, places: 1)), from \(F.money(e.prevClose, cents: true)) to \(F.money(e.close, cents: true)). Day 1 closed."
        if settled, let p = row.e.day2Pct { s += " Day 2 \(p >= 0 ? "up" : "down") \(F.pct(p, places: 1))." }
        else { s += " Day 2 closes \(row.when)." }
        return s
    }
}

/// A 16 circle in ink with a 10 pt check once that day's close is in; an
/// empty 1.5 pt ring until then. Fill and check fade 0.3 s.
struct DayTick: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().fill(on ? S.ink : Color.clear)
            Circle().strokeBorder(S.muted, lineWidth: 1.5).opacity(on ? 0 : 1)
            Path { p in p.move(to: CGPoint(x: 2, y: 5.2)); p.addLine(to: CGPoint(x: 4, y: 7.2)); p.addLine(to: CGPoint(x: 8, y: 3)) }
                .stroke(S.paper, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: 10, height: 10)
                .opacity(on ? 1 : 0)
        }
        .frame(width: 16, height: 16)
        .animation(.easeOut(duration: 0.3), value: on)
        .accessibilityHidden(true)
    }
}

// MARK: - The deck card (block 03b)

struct SunnyAftershockCard: View {
    let data: Aftershock
    let calendar: [CalendarDay]
    let onTap: () -> Void
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme
    @State private var motion = OrbitMotion()
    @State private var reveal: Date?
    @State private var seen: AftershockScan.Mode?
    @State private var width: CGFloat = 353
    /// The orbit and words stop when the card is scrolled off the page.
    @State private var onScreen = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: S.rDeck, style: .continuous)
        ZStack(alignment: .topLeading) {
            S.night
            orbit
            TimelineView(.animation(minimumInterval: 0.1, paused: !onScreen)) { _ in
                let now = SClock.now()
                let m = AftershockScan.at(now, data, calendar: calendar)
                let fr = m.frame(now, reveal: reveal, pending: pending(m), reduce: reduce)
                let w = Self.words(m, fr)
                Button(action: onTap) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("AFTERSHOCK").sType(SType(size: 13, weight: 700, line: 16, tracking: 0.06), tabular: false)
                        Spacer(minLength: 0)
                        HStack(alignment: .bottom, spacing: 0) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(SWrap.lines(w.0, SunnyDeckCard.title, width: 230, .balance))
                                    .sType(SunnyDeckCard.title)
                                    .fixedSize()
                                    .contentTransition(fr.mode == .scan ? .identity : .numericText())
                                    .animation(reduce || fr.mode == .scan ? nil : S.standard(S.roll), value: w.0)
                                Text(SWrap.lines(w.1, SunnyDeckCard.sub, width: width - 44 - 64, .pretty))
                                    .sType(SunnyDeckCard.sub, tabular: false)
                                    .foregroundStyle(Color.white.opacity(0.82))
                                    .fixedSize()
                                    .contentTransition(.opacity)
                                    .animation(.easeOut(duration: 0.3), value: w.1)
                            }
                            Spacer(minLength: 16)
                            arrow
                        }
                    }
                    .foregroundStyle(Color.white)
                    .padding(S.padDeck)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SPressStyle(scale: 0.98))
                .accessibilityLabel("Aftershock. \(w.0). \(w.1)")
                .onChange(of: m.mode) { old, new in
                    seen = new
                    if old == .scan, new == .done || new == .none, !reduce { reveal = now }
                }
            }
            Button(action: onDismiss) {
                SCross(half: 6).stroke(Color.white, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle().inset(by: -6))
            }
            .buttonStyle(SPressStyle())
            .opacity(0.7)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 14).padding(.trailing, 14)
            .accessibilityLabel("Dismiss")
        }
        .frame(height: 184)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onScrollVisibilityChange(threshold: 0.01) { onScreen = $0 }
        .clipShape(shape)
        .overlay { if scheme == .dark { shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1) } }
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.08), radius: 1.5, y: 1)
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.25), radius: 12, y: 10)
        .onAppear {
            seen = AftershockScan.at(SClock.now(), data, calendar: calendar).mode
            #if DEBUG && targetEnvironment(simulator)
            if DebugPreset.bool("as.reveal") { reveal = SClock.now() }
            #endif
        }
    }

    private func pending(_ m: AftershockScan) -> Bool {
        reveal == nil && seen == .scan && (m.mode == .done || m.mode == .none) && !reduce
    }

    /// The page orbit at 0.52, centered 77 in from the right and 84 down,
    /// white on the night fill, no ticker labels; 30 frames a second.
    private var orbit: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !onScreen)) { ctx in
            let now = SClock.now()
            let m = AftershockScan.at(now, data, calendar: calendar)
            let fr = m.frame(now, reveal: reveal, pending: pending(m), reduce: reduce)
            Canvas { g, size in
                var c = g
                let s = 0.52
                c.translateBy(x: size.width - 77 - 176.5 * s, y: 84 - 158 * s)
                c.scaleBy(x: s, y: s)
                AftershockOrbit.draw(c, fr: fr, crashes: m.top.map(\.e.ticker), universe: m.universe,
                                     motion: motion, clock: ctx.date.timeIntervalSinceReferenceDate, reduce: reduce,
                                     ink: S.ink, red: S.red, k: 1, labels: false)
            }
            .environment(\.colorScheme, .dark)
        }
        .accessibilityHidden(true)
    }

    private var arrow: some View {
        Text("→")
            .font(SType(size: 22, weight: 700, line: 22, tracking: 0).font())
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.white.opacity(0.14)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    /// Title and line for each state (block 03b, Title and line).
    static func words(_ m: AftershockScan, _ fr: AftershockFrame) -> (String, String) {
        let u = m.universe
        switch fr.mode {
        case .wait:
            return ("Scan at 4:15", "Day 2 · " + m.top.map(\.e.ticker).joined(separator: ", ") + " today")
        case .soon: return ("Scan in \(fr.clock)", "\(u) names after the close")
        case .scan:
            return ("\(fr.count) of \(u)", fr.found == 0 ? "Scanning for drops of 15% or more" : "Scanning · \(fr.found) found so far")
        case .done:
            let n = m.top.count, shown = m.top.prefix(3).map { "\($0.e.ticker) \(F.pct($0.e.dropPct, places: 1))" }
            return ("\(n) crash\(n == 1 ? "" : "es")", (shown + (n > 3 ? ["\(n - 3) more"] : [])).joined(separator: " · "))
        case .none: return ("All clear", "No crashes · next scan \(m.nextDay) 4:15 PM")
        }
    }
}
