//
//  DeckCards.swift
//  Sunny
//
//  Which cards are in the Home deck today (blocks 03 to 07), in the deck's
//  order: Earnings · Earnings season · Theta check · Report · Holiday. Each
//  kind keeps its own rule for when it comes and goes; this works them out
//  from the Home payload and the saved calendar, in New York time, on open,
//  on every refresh and at midnight.
//

import SwiftUI

struct DeckCard: Identifiable, Equatable {
    enum Tone: Equatable { case yellow, ink, green, frosted }
    enum Action: Equatable { case writes(String), report(Int), theta(String) }

    let id: String
    let kicker: String
    let title: String
    let sub: String
    let mark: String
    let tone: Tone
    let action: Action?
    /// Key a ✕ files the card under, and until when (yyyy-MM-dd, inclusive).
    let dismiss: (key: String, until: String)?

    static func == (a: DeckCard, b: DeckCard) -> Bool {
        a.id == b.id && a.kicker == b.kicker && a.title == b.title && a.sub == b.sub && a.mark == b.mark
    }
}

/// Cards dismissed with ✕, kept on the phone: key → last day hidden.
enum DeckDismissals {
    private static let key = "sunny.deck.dismissed"
    static func all() -> [String: String] { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
    static func hidden(_ k: String, today: String) -> Bool { (all()[k] ?? "") >= today }
    static func hide(_ k: String, until: String, today: String) {
        var d = all().filter { $0.value >= today }        // drop the stale ones
        d[k] = until
        UserDefaults.standard.set(d, forKey: key)
    }
}

enum DeckBuilder {
    static let weekdays = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let longDays = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let months = ["January", "February", "March", "April", "May", "June", "July", "August",
                         "September", "October", "November", "December"]

    static func weekday(_ iso: String) -> Int { MarketClock.addDays(iso, 0).weekday }
    static func dayNum(_ iso: String) -> String { String(Int(iso.suffix(2)) ?? 0) }

    static func cards(_ h: HomePayload) -> [DeckCard] {
        let today = h.today
        var out: [DeckCard] = []
        out += earnings(h, today)
        if let s = season(h, today) { out.append(s) }
        out += (h.deck.thetaChecks ?? []).filter(\.cardToday).map(theta)
        out += reports(h)
        if let x = holiday(h, today) { out.append(x) }
        return out.filter { c in c.dismiss.map { !DeckDismissals.hidden($0.key, today: today) } ?? true }
    }

    // MARK: 04 · Earnings, one trading day ahead

    private static func earnings(_ h: HomePayload, _ today: String) -> [DeckCard] {
        let next = MarketClock.nextTrading(after: today, h.calendar).iso
        let due = h.deck.earnings.filter { e in
            (e.date == today && (e.time == "amc" || e.time == nil)) || (e.date == next && e.time != "amc")
        }.sorted { abs($0.exposure) > abs($1.exposure) }
        let card = { (e: Deck.Earning) -> DeckCard in
            let wd = weekday(e.date)
            let title: String
            switch e.time {
            case "amc": title = "\(e.ticker) reports after close"
            case "bmo": title = "\(e.ticker) reports before the open"
            default: title = "\(e.ticker) reports today"
            }
            var held: [String] = []
            if e.shares > 0 { held.append("\(Int(e.shares)) shares") }
            if e.callsOn > 0 { held.append("\(e.callsOn) calls") }
            if e.putsOn > 0 { held.append("\(e.putsOn) puts") }
            let on = e.callsOn + e.putsOn == 0 ? held.joined(separator: ", ") + ", nothing sold" : held.joined(separator: ", ") + " on"
            let sub = [e.pricedMovePct.map { "±\(F.trim($0))% move" }, on].compactMap { $0 }.joined(separator: " · ")
            return DeckCard(id: "earn-\(e.ticker)-\(e.date)", kicker: "Earnings · \(weekdays[wd]) \(dayNum(e.date))",
                            title: title, sub: sub, mark: dayNum(e.date), tone: .yellow,
                            action: .writes(e.ticker), dismiss: ("earn-\(e.ticker)-\(e.date)", today))
        }
        // One card per name up to three; past that, one card for the rest.
        if due.count <= 3 { return due.map(card) }
        let rest = Array(due.dropFirst(3))
        let tonight = rest.allSatisfy { $0.date == today }
        let summary = DeckCard(
            id: "earn-more-\(today)", kicker: "Earnings · \(weekdays[weekday(rest[0].date)]) \(dayNum(rest[0].date))",
            title: "\(rest.count) names report \(tonight ? "tonight" : "tomorrow")",
            sub: rest.map(\.ticker).joined(separator: ", "), mark: dayNum(rest[0].date), tone: .yellow,
            action: .writes(rest[0].ticker), dismiss: ("earn-more-\(today)", today))
        return due.prefix(3).map(card) + [summary]
    }

    // MARK: 04b · Earnings season, its first week

    private static func season(_ h: HomePayload, _ today: String) -> DeckCard? {
        guard let s = h.deck.season, s.names > 0, s.starts <= today, today <= s.showThrough else { return nil }
        let sub: String
        if let one = s.only { sub = "\(one.ticker) reports \(F.day(one.date))" }
        else { sub = "\(s.names) of your names report by \(F.day(s.last ?? s.ends))" }
        return DeckCard(id: "season-\(s.quarter)-\(s.starts)", kicker: "Earnings season · \(s.quarter)",
                        title: "Earnings season starts now", sub: sub, mark: s.quarter, tone: .frosted,
                        action: nil, dismiss: ("season-\(s.quarter)-\(s.starts)", s.ends))
    }

    // MARK: 07 · Theta check, the day it is found

    private static func theta(_ c: Deck.ThetaCheck) -> DeckCard {
        let sub: String
        if c.trigger == "growth", let g = c.growthPct { sub = "Long theta is up \(Int(g.rounded()))% this month" }
        else if let w = c.ratioNow { sub = "It alone pulls theta to \(F.level(w))×" }
        else { sub = "Long theta is dragging" }
        return DeckCard(id: "theta-\(c.leg)", kicker: "Theta check", title: "Time to roll the \(c.ticker) longs",
                        sub: sub, mark: "θ", tone: .ink, action: .theta(c.leg), dismiss: nil)
    }

    // MARK: 06 · Reports, Monday and the 1st

    private static func reports(_ h: HomePayload) -> [DeckCard] {
        (h.deck.reports ?? []).enumerated().compactMap { i, r in
            guard r.pending == nil, let p = r.period else { return nil }
            let (kicker, sub, mark) = reportWords(r, p)
            return DeckCard(id: "report-\(r.kind)-\(p.from)", kicker: kicker, title: "Your report is ready",
                            sub: sub, mark: mark, tone: .green, action: .report(i), dismiss: nil)
        }
    }

    /// "Week 41" · "Weekly report · Oct 5 - 9" · "41", or "September" ·
    /// "Monthly report · Sep 1 - 30" · "09".
    static func reportWords(_ r: Deck.Report, _ p: Deck.Report.Period) -> (String, String, String) {
        let to = lastTrading(onOrBefore: p.to)
        let span = p.from.prefix(7) == to.prefix(7)
            ? "\(F.day(p.from)) - \(dayNum(to))" : "\(F.day(p.from)) - \(F.day(to))"
        if r.kind == "monthly" {
            let m = Int(p.from.dropFirst(5).prefix(2)) ?? 1
            let end = p.to
            return (months[m - 1], "Monthly report · \(F.day(p.from)) - \(dayNum(end))", String(format: "%02d", m))
        }
        return ("Week \(r.mark)", "Weekly report · \(span)", r.mark)
    }

    static func lastTrading(onOrBefore iso: String) -> String {
        var x = MarketClock.addDays(iso, 0)
        while x.weekday == 1 || x.weekday == 7 { x = MarketClock.addDays(x.iso, -1) }
        return x.iso
    }

    // MARK: 05 · Holiday, the last trading day before a closure

    private static func holiday(_ h: HomePayload, _ today: String) -> DeckCard? {
        // The next weekday after today.
        var n = MarketClock.addDays(today, 1)
        while n.weekday == 1 || n.weekday == 7 { n = MarketClock.addDays(n.iso, 1) }
        guard let c = MarketClock.closure(n.iso, h.calendar) else { return nil }
        let wd = n.weekday
        if c.kind == "closed" {
            // Not on a closed day itself: the status line says so.
            let t = MarketClock.ny(Date())
            guard MarketClock.isTradingDay(today, weekday: t.weekday, h.calendar) else { return nil }
            let expiry = wd == 6 ? "weeklies expire Thursday" : "weeklies expire Friday as usual"
            return DeckCard(id: "hol-\(n.iso)", kicker: "Holiday · \(weekdays[wd]) \(dayNum(n.iso))",
                            title: "Market closed \(longDays[wd])", sub: "\(c.name) · \(expiry)",
                            mark: dayNum(n.iso), tone: .frosted, action: nil, dismiss: ("hol-\(n.iso)", today))
        }
        let at = MarketClock.clock(MarketClock.closeMinutes(n.iso, h.calendar))
        return DeckCard(id: "early-\(n.iso)", kicker: "Early close · \(weekdays[wd]) \(dayNum(n.iso))",
                        title: "Market closes at \(at) \(longDays[wd])", sub: "\(c.name) · options stop at \(at)",
                        mark: dayNum(n.iso), tone: .frosted, action: nil, dismiss: ("early-\(n.iso)", today))
    }
}
