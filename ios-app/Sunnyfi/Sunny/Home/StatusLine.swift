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

    static func addDays(_ iso: String, _ n: Int) -> (iso: String, weekday: Int) {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
        let f = DateFormatter(); f.calendar = cal; f.timeZone = ny; f.dateFormat = "yyyy-MM-dd"
        let d = cal.date(byAdding: .day, value: n, to: f.date(from: iso)!)!
        return (f.string(from: d), cal.component(.weekday, from: d))
    }
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
    enum Tone { case grey, amber, red, green }
    let text: String
    let tone: Tone

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
                return .init(text: "\(named) · opens \(MarketClock.dayName[next.weekday]) 9:30", tone: .grey)
            }
            return .init(text: "Weekend · opens \(MarketClock.dayName[next.weekday]) 9:30", tone: .grey)
        }
        let close = MarketClock.closeMinutes(t.date, cal), open = 9 * 60 + 30
        if m < 4 * 60 { return .init(text: "Closed · opens 9:30", tone: .grey) }
        if m < open - 30 { return .init(text: "Pre-market · opens 9:30", tone: .amber) }
        if m < open { return .init(text: "Opens in \(open - m)m", tone: .amber) }
        if m < close - 30 {
            return close < 16 * 60
                ? .init(text: "Market open · closes \(MarketClock.clock(close))", tone: .green)
                : .init(text: "Market open", tone: .green)
        }
        if m < close - 10 { return .init(text: "Closes in \(close - m)m", tone: .amber) }
        if m < close { return .init(text: "Closes in \(close - m)m", tone: .red) }
        // After the bell: the 4:15 tail for names in the book that trade it.
        if m < close + 15, !held415.isEmpty {
            return .init(text: "After hours · \(held415.joined(separator: ", ")) until \(MarketClock.clock(close + 15))", tone: .amber)
        }
        // The evening before a closure says so.
        if let c = MarketClock.closure(MarketClock.addDays(t.date, 1).iso, cal), c.kind == "closed" {
            return .init(text: "Closed tomorrow · \(c.name)", tone: .grey)
        }
        if t.weekday == 6 || next.iso != MarketClock.addDays(t.date, 1).iso {
            return .init(text: "After hours · opens \(nextWhen)", tone: .grey)
        }
        return .init(text: m < 20 * 60 ? "After hours · opens 9:30" : "Closed · opens 9:30", tone: .grey)
    }
}

// MARK: - View

struct StatusLine: View {
    let store: HomeStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { ctx in
            let home = store.home
            let st = MarketStatus.at(ctx.date, calendar: home?.calendar ?? [], held415: home?.tradeTo415 ?? [])
            HStack(spacing: 8) {
                Circle().fill(dot(st.tone)).frame(width: 6, height: 6)
                Text(st.text)
                    .sType(.kicker.sized(13, line: 13).weighted(600), tabular: false)
                    .foregroundStyle(textColor(st.tone))
                    .lineLimit(1)
                Spacer(minLength: 8)
                UpdatedPill(store: store, now: ctx.date, open: st.tone != .grey)
            }
            .frame(height: 28)
            .accessibilityElement(children: .combine)
        }
    }

    private func dot(_ t: MarketStatus.Tone) -> Color {
        switch t { case .grey: S.muted; case .amber: S.yellow; case .red: S.red; case .green: S.green }
    }
    private func textColor(_ t: MarketStatus.Tone) -> Color {
        switch t { case .grey: S.muted; case .amber: S.yellowDeep; case .red: S.red; case .green: S.ink }
    }
}

/// "Updated 16:04" · green "Live · just now" for 2 s after an update · red
/// with the reason when the market is open and updates stop. Tap = refresh.
struct UpdatedPill: View {
    let store: HomeStore
    let now: Date
    let open: Bool

    var body: some View {
        let (text, color) = label
        Button { Task { await store.refresh() } } label: {
            HStack(spacing: 6) {
                Circle().fill(color == S.muted ? S.muted : color).frame(width: 5, height: 5)
                Text(text).sType(.label, tabular: true).foregroundStyle(color)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(SPressStyle())
        .accessibilityLabel(text)
        .accessibilityHint("Refreshes now")
    }

    private var label: (String, Color) {
        guard let g = store.lastGood else { return ("Updating", S.muted) }
        let f = DateFormatter(); f.timeZone = MarketClock.ny; f.dateFormat = "H:mm"
        let at = f.string(from: g)
        if open {
            switch store.health {
            case .notUpdating: return ("Not updating · \(at)", S.red)
            case .offline: return ("No connection · \(at)", S.red)
            case .cantReach: return ("Can't reach prices · \(at)", S.red)
            case .fresh: break
            }
            if now.timeIntervalSince(g) < 2.5 { return ("Live · just now", S.green) }
        }
        let sameDay = MarketClock.ny(g).date == MarketClock.ny(now).date
        if !sameDay {
            let d = DateFormatter(); d.timeZone = MarketClock.ny; d.dateFormat = "EEE H:mm"
            return ("Updated \(d.string(from: g))", S.muted)
        }
        return ("Updated \(at)", S.muted)
    }
}
