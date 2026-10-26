//
//  StatusLine.swift
//  Sunny
//
//  Block 01 · Market status · Updated. Which session the market is in and
//  what comes next, in New York time, from the saved exchange calendar (never
//  hard-coded), and the Updated pill: the last good update, red with the
//  reason when updates stop while the market is open.
//
//  Wording and colours follow the block's gallery (Build Blocks #b01):
//  grey = closed · amber = opens or closes within 30 min, pre-market and the
//  4:15 tail · red = closes within 10 min · green = open.
//

import SwiftUI

// MARK: - Clock

enum MarketClock {
    static let ny = TimeZone(identifier: "America/New_York")!

    struct NYTime { let date: String; let weekday: Int; let minutes: Int }   // weekday 1 = Sunday

    static func ny(_ d: Date) -> NYTime {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
        let c = cal.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: d)
        return NYTime(date: String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!),
                      weekday: c.weekday!, minutes: c.hour! * 60 + c.minute!)
    }

    static func closure(_ iso: String, _ cal: [CalendarDay]) -> CalendarDay? { cal.first { $0.date == iso } }
    static func isTradingDay(_ iso: String, weekday: Int, _ cal: [CalendarDay]) -> Bool {
        weekday != 1 && weekday != 7 && closure(iso, cal)?.kind != "closed"
    }
    /// Minutes after midnight the regular session ends (13:00 on an early close).
    static func closeMinutes(_ iso: String, _ cal: [CalendarDay]) -> Int {
        guard let c = closure(iso, cal), c.kind == "early_close", let t = c.closes else { return 16 * 60 }
        let p = t.split(separator: ":").compactMap { Int($0) }
        return p.count >= 2 ? p[0] * 60 + p[1] : 16 * 60
    }

    /// 4:00 to 20:00 New York on a trading day: the 30 s tick runs (block 25).
    static func inSession(_ d: Date, calendar: [CalendarDay]) -> Bool {
        let t = ny(d)
        return isTradingDay(t.date, weekday: t.weekday, calendar) && t.minutes >= 4 * 60 && t.minutes < 20 * 60
    }

    /// 18:00 to the 9:30 open, from the evening before a trading day: the Today cards show where the index
    /// futures point and the app keeps updating (Nik, 25 Oct 2026: "every night from 6 PM"). Not Friday or
    /// Saturday night, nor the night before a market holiday.
    static func futuresNight(_ d: Date, calendar: [CalendarDay]) -> Bool {
        let t = ny(d)
        if t.minutes >= 18 * 60 { let n = addDays(t.date, 1); return isTradingDay(n.iso, weekday: n.weekday, calendar) }
        return t.minutes < 9 * 60 + 30 && isTradingDay(t.date, weekday: t.weekday, calendar)
    }

    /// 9:30 to the close on a trading day.
    static func isRegular(_ d: Date, calendar: [CalendarDay]) -> Bool {
        let t = ny(d)
        return isTradingDay(t.date, weekday: t.weekday, calendar) && t.minutes >= 9 * 60 + 30
            && t.minutes < closeMinutes(t.date, calendar)
    }

    static func addDays(_ iso: String, _ n: Int) -> (iso: String, weekday: Int) {
        let d = nyCal.date(byAdding: .day, value: n, to: isoDay.date(from: iso)!)!
        return (isoDay.string(from: d), nyCal.component(.weekday, from: d))
    }
    /// Made once: a DateFormatter per call was a top cost on every redraw.
    private static let nyCal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = ny; return c }()
    nonisolated(unsafe) private static let isoDay: DateFormatter = {
        let f = DateFormatter(); f.calendar = nyCal; f.timeZone = ny; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    /// The next trading day after `iso`.
    static func nextTrading(after iso: String, _ cal: [CalendarDay]) -> (iso: String, weekday: Int) {
        var x = addDays(iso, 1)
        while !isTradingDay(x.iso, weekday: x.weekday, cal) { x = addDays(x.iso, 1) }
        return x
    }
    static let dayName = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static func clock(_ m: Int) -> String {
        let h = m / 60, mm = m % 60, h12 = h > 12 ? h - 12 : h
        return mm == 0 ? "\(h12):00" : String(format: "%d:%02d", h12, mm)
    }
}

// MARK: - Status

struct MarketStatus: Equatable {
    enum Tone { case grey, amber, red, green, ink }
    let text: String
    /// The dot's colour and the words' colour (they differ in pre-market:
    /// a yellow dot over grey words, as the gallery draws it).
    let dot: Tone
    let ink: Tone
    /// Prices are moving: the pill may say "Live" or turn red when stuck.
    let live: Bool

    static func grey(_ t: String) -> MarketStatus { .init(text: t, dot: .grey, ink: .grey, live: false) }

    /// Block 01's states, in the order the gallery lists them.
    static func at(_ now: Date, calendar cal: [CalendarDay], held415: [String]) -> MarketStatus {
        let t = MarketClock.ny(now)
        let m = t.minutes
        let trading = MarketClock.isTradingDay(t.date, weekday: t.weekday, cal)
        let next = MarketClock.nextTrading(after: t.date, cal)
        let nextWhen = next.iso == MarketClock.addDays(t.date, 1).iso ? "9:30" : "\(MarketClock.dayName[next.weekday]) 9:30"

        if !trading {
            if let c = MarketClock.closure(t.date, cal), c.kind == "closed" {
                let named = c.name == "Market closed" ? "Closed today" : c.name
                return .grey("\(named) · opens \(MarketClock.dayName[next.weekday]) 9:30")
            }
            return .grey("Weekend · opens \(MarketClock.dayName[next.weekday]) 9:30")
        }
        let close = MarketClock.closeMinutes(t.date, cal), open = 9 * 60 + 30
        if m < 4 * 60 { return .grey("Closed · opens 9:30") }
        if m < open - 30 { return .init(text: "Pre-market · opens 9:30", dot: .amber, ink: .grey, live: false) }
        if m < open { return .init(text: "Opens in \(open - m)m", dot: .amber, ink: .amber, live: false) }
        if m < close - 30 {
            let txt = close < 16 * 60 ? "Market open · closes \(MarketClock.clock(close))" : "Market open"
            return .init(text: txt, dot: .green, ink: .ink, live: true)
        }
        if m < close - 10 { return .init(text: "Closes in \(close - m)m", dot: .amber, ink: .amber, live: true) }
        if m < close { return .init(text: "Closes in \(close - m)m", dot: .red, ink: .red, live: true) }
        // After the bell: the 4:15 tail for names in the book that trade it.
        if m < close + 15, !held415.isEmpty {
            return .init(text: "After hours · \(held415.joined(separator: ", ")) until \(MarketClock.clock(close + 15))",
                         dot: .amber, ink: .amber, live: true)
        }
        // The evening before a closure says so.
        if let c = MarketClock.closure(MarketClock.addDays(t.date, 1).iso, cal), c.kind == "closed" {
            return .grey("Closed tomorrow · \(c.name)")
        }
        if t.weekday == 6 || next.iso != MarketClock.addDays(t.date, 1).iso {
            return .grey("After hours · opens \(nextWhen)")
        }
        return .grey(m < 20 * 60 ? "After hours · opens 9:30" : "Closed · opens 9:30")
    }
}

// MARK: - View

struct StatusLine: View {
    let store: HomeStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { ctx in
            let home = store.home
            let now = SClock.override ?? ctx.date
            let st = MarketStatus.at(now, calendar: home?.calendar ?? [], held415: home?.tradeTo415 ?? [])
            // space-between with a 12 gap (one gap, not one each side of a spacer)
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(color(st.dot, dot: true)).frame(width: 8, height: 8)
                    Text(st.text)
                        .sType(.kicker.sized(13, line: 13).weighted(600), tabular: false)
                        .foregroundStyle(color(st.ink, dot: false))
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                UpdatedPill(store: store, now: now, live: st.live)
            }
            .frame(height: 28)
            .accessibilityElement(children: .combine)
        }
    }

    private func color(_ t: MarketStatus.Tone, dot: Bool) -> Color {
        switch t {
        case .grey: S.muted
        case .amber: dot ? S.yellow : S.yellowDeep
        case .red: S.red
        case .green: S.green
        case .ink: S.ink
        }
    }
}

/// "Updated 16:04" · green "Live · just now" for 2.5 s after an update · red
/// with the reason when prices should be moving and updates stop. Closed,
/// it shows when prices last moved: "Updated 16:15", "Updated Fri 16:15", or
/// the day alone on a market holiday. Tap = refresh.
struct UpdatedPill: View {
    let store: HomeStore
    let now: Date
    let live: Bool

    var body: some View {
        let (text, color) = label
        Button { Task { await store.refresh(.pull) } } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(text).sType(.label, tabular: true).foregroundStyle(color)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .glassEffect(.regular, in: .capsule)
            .contentShape(Capsule().inset(by: -8))
        }
        .buttonStyle(SPressStyle())
        .accessibilityLabel(text)
        .accessibilityHint("Refreshes now")
    }

    private func fmt(_ d: Date, _ f: String) -> String {
        let x = DateFormatter(); x.timeZone = MarketClock.ny; x.dateFormat = f; return x.string(from: d)
    }

    private var label: (String, Color) {
        guard let g = store.lastGood else { return ("Updating", S.muted) }
        if live {
            let at = fmt(g, "H:mm")
            switch store.health {
            case .notUpdating: return ("Not updating · \(at)", S.red)
            case .offline: return ("No connection · \(at)", S.red)
            case .cantReach: return ("Can't reach prices · \(at)", S.red)
            case .fresh: break
            }
            if now.timeIntervalSince(g) < 2.5 { return ("Live · just now", S.green) }
            return ("Updated \(at)", S.muted)
        }
        // Closed or not yet open: the last time prices moved.
        let t = MarketClock.ny(now)
        let pre = t.minutes >= 4 * 60 && t.minutes < 9 * 60 + 30
            && MarketClock.isTradingDay(t.date, weekday: t.weekday, store.home?.calendar ?? [])
        let last = pre ? g : (store.home?.fresh.marks.flatMap(Self.iso) ?? g)
        if MarketClock.ny(last).date == t.date { return ("Updated \(fmt(last, "H:mm"))", S.muted) }
        let holiday = MarketClock.closure(t.date, store.home?.calendar ?? [])?.kind == "closed"
        return (holiday ? "Updated \(fmt(last, "EEE"))" : "Updated \(fmt(last, "EEE H:mm"))", S.muted)
    }

    static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
