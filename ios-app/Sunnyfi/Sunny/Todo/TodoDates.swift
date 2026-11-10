//
//  TodoDates.swift
//  Sunny
//
//  To do (handoff 2026-11-10-todo, SunnyTodo.dc.html): the dates as words (`lab`, `due`, `full`) and the dates typed
//  in the text (`parse`), ported line for line from the design's logic class. Days are yyyy-MM-dd strings worked at
//  noon UTC, so no time zone moves a day. "Today" is New York's day (Nik, 10 Nov 2026).
//

import Foundation

enum TodoDates {
    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let monthsShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let monthsLong = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    nonisolated(unsafe) private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    nonisolated(unsafe) private static let nyDay: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let lock = NSLock()

    /// Today in New York, as yyyy-MM-dd.
    static func today(_ now: Date = Date()) -> String { lock.lock(); defer { lock.unlock() }; return nyDay.string(from: now) }

    /// y, m (1-12), d of a yyyy-MM-dd string.
    static func ymd(_ s: String) -> (y: Int, m: Int, d: Int)? {
        let p = s.prefix(10).split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? (p[0], p[1], p[2]) : nil
    }
    /// A day from its parts; the parts may run over (month 13, day 32) and roll on, as JavaScript's Date does.
    static func make(_ y: Int, _ m: Int, _ d: Int) -> String {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
        guard let x = utc.date(from: c) else { return "" }
        let r = utc.dateComponents([.year, .month, .day], from: x)
        return String(format: "%04d-%02d-%02d", r.year ?? y, r.month ?? m, r.day ?? d)
    }
    static func plus(_ s: String, _ n: Int) -> String {
        guard let p = ymd(s) else { return s }
        return make(p.y, p.m, p.d + n)
    }
    /// Sunday 0 to Saturday 6.
    static func weekday(_ s: String) -> Int {
        guard let p = ymd(s) else { return 0 }
        var c = DateComponents(); c.year = p.y; c.month = p.m; c.day = p.d; c.hour = 12
        guard let x = utc.date(from: c) else { return 0 }
        return utc.component(.weekday, from: x) - 1
    }
    /// b less a, in days.
    static func days(from a: String, to b: String) -> Int {
        guard let pa = ymd(a), let pb = ymd(b) else { return 0 }
        var ca = DateComponents(); ca.year = pa.y; ca.month = pa.m; ca.day = pa.d; ca.hour = 12
        var cb = DateComponents(); cb.year = pb.y; cb.month = pb.m; cb.day = pb.d; cb.hour = 12
        guard let x = utc.date(from: ca), let y = utc.date(from: cb) else { return 0 }
        return Int((y.timeIntervalSince(x) / 86_400).rounded())
    }
    /// Days in a month (m 1-12).
    static func daysIn(_ y: Int, _ m: Int) -> Int { ymd(make(y, m + 1, 0))?.d ?? 30 }

    /// A day as the list writes it: Today, Tomorrow, Day after, Yesterday, the weekday within the week, "3 days ago",
    /// else "Tue Nov 3" ("Mon Jan 4, 2027" in another year).
    static func lab(_ s: String?, today t: String) -> String {
        guard let s, let p = ymd(s), let pt = ymd(t) else { return "" }
        let n = days(from: t, to: s), wd = weekday(s)
        if n == 0 { return "Today" }
        if n == 1 { return "Tomorrow" }
        if n == 2 { return "Day after" }
        if n == -1 { return "Yesterday" }
        if n > 2 && n < 7 { return weekdays[wd] }
        if n < -1 && n > -7 { return "\(-n) days ago" }
        return "\(weekdays[wd].prefix(3)) \(monthsShort[p.m - 1]) \(p.d)" + (p.y != pt.y ? ", \(p.y)" : "")
    }
    /// The preview line's words: "due tomorrow", "due the day after tomorrow", "due Friday", "due Tue Nov 3".
    static func due(_ s: String, today t: String) -> String {
        let l = lab(s, today: t)
        if l == "Day after" { return "the day after tomorrow" }
        if ["Today", "Tomorrow", "Yesterday"].contains(l) { return l.lowercased() }
        return l
    }
    /// "Tuesday, October 27" (a calendar day read aloud).
    static func full(_ s: String) -> String {
        guard let p = ymd(s) else { return s }
        return "\(weekdays[weekday(s)]), \(monthsLong[p.m - 1]) \(p.d)"
    }

    // MARK: Typed dates

    private static let num: [String: Int] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                                             "seven": 7, "eight": 8, "nine": 9, "ten": 10]
    private static let wk: [String: Int] = ["sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6]
    private static let mo: [String: Int] = ["jan": 0, "feb": 1, "mar": 2, "apr": 3, "may": 4, "jun": 5, "jul": 6, "aug": 7,
                                            "sep": 8, "oct": 9, "nov": 10, "dec": 11]
    private static let WR = "mon(?:day)?|tue(?:s(?:day)?)?|wed(?:s|nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?"
    private static let MR = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }

    /// The patterns in the design's order; each gives the day for a match (nil when it is not a real day).
    private static let patterns: [(NSRegularExpression, (_ g: [String?], _ t: String) -> String?)] = [
        (re(#"\b(?:the\s+)?day\s+after\s+(?:tomorrow|tmrw)\b"#), { _, t in plus(t, 2) }),
        (re(#"\b(?:the\s+)?day\s+after\b"#), { _, t in plus(t, 2) }),
        (re(#"\b(?:today|tonight|tonite|eod)\b"#), { _, t in t }),
        (re(#"\b(?:tomorrow|tmrw|tmr|tmw)\b"#), { _, t in plus(t, 1) }),
        (re(#"\bin\s+(\d{1,3}|an?|one|two|three|four|five|six|seven|eight|nine|ten)\s+(day|week|month)s?\b"#), { g, t in
            let w = (g[1] ?? "").lowercased(), n = num[w] ?? Int(w) ?? 0, u = (g[2] ?? "").lowercased()
            if u == "day" { return plus(t, n) }
            if u == "week" { return plus(t, 7 * n) }
            guard let p = ymd(t) else { return nil }
            return make(p.y, p.m + n, p.d)
        }),
        (re(#"\bnext\s+week\b"#), { _, t in let t0 = weekday(t), n = (1 - t0 + 7) % 7; return plus(t, n == 0 ? 7 : n) }),
        (re(#"\bnext\s+month\b"#), { _, t in guard let p = ymd(t) else { return nil }; return make(p.y, p.m + 1, 1) }),
        (re(#"\b(?:(?:the|this)\s+)?weekend\b"#), { _, t in plus(t, (6 - weekday(t) + 7) % 7) }),
        (re(#"\bend\s+of\s+(?:the\s+)?week\b|\beow\b"#), { _, t in plus(t, (5 - weekday(t) + 7) % 7) }),
        (re(#"\bend\s+of\s+(?:the\s+)?month\b|\beom\b"#), { _, t in guard let p = ymd(t) else { return nil }; return make(p.y, p.m + 1, 0) }),
        (re("\\b(?:(this|next)\\s+)?(" + WR + ")\\b"), { g, t in
            guard let w = wk[String((g[2] ?? "").prefix(3)).lowercased()] else { return nil }
            return weekdayFrom(t, w, g[1]?.lowercased())
        }),
        (re("\\b(" + MR + ")\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b"), { g, t in
            guard let m = mo[String((g[1] ?? "").prefix(3)).lowercased()], let d = Int(g[2] ?? "") else { return nil }
            return monthDay(t, m, d)
        }),
        (re("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?(" + MR + ")\\b"), { g, t in
            guard let m = mo[String((g[2] ?? "").prefix(3)).lowercased()], let d = Int(g[1] ?? "") else { return nil }
            return monthDay(t, m, d)
        }),
        (re(#"\b(\d{1,2})/(\d{1,2})\b"#), { g, t in
            guard let m = Int(g[1] ?? ""), let d = Int(g[2] ?? "") else { return nil }
            return monthDay(t, m - 1, d)
        }),
    ]

    /// The design's wd(): the next such weekday, never today; "this" may be today; "next" is the one in the following week.
    private static func weekdayFrom(_ t: String, _ w: Int, _ mod: String?) -> String {
        let t0 = weekday(t)
        var n = (w - t0 + 7) % 7
        if mod == "this" { return plus(t, n) }
        if n == 0 { n = 7 }
        if mod == "next" && n <= (7 - t0) % 7 { n += 7 }
        return plus(t, n)
    }
    /// The design's md(): month (0-11) and day this year, or next year once the day has passed; nil when not a real day.
    private static func monthDay(_ t: String, _ m: Int, _ d: Int) -> String? {
        guard (0...11).contains(m), (1...31).contains(d), let pt = ymd(t) else { return nil }
        let s = make(pt.y, m + 1, d)
        guard let p = ymd(s), p.m == m + 1 else { return nil }
        return s < t ? make(pt.y + 1, m + 1, d) : s
    }

    private static let leadIn = re(#"\b(?:by|on|due|before|for|until|till)\s+$"#)
    private static let spaces = re(#"\s+"#)
    private static let beforePunct = re(#"\s+([,.;:!?])"#)
    private static let ends = re(#"^[\s,;:-]+|[\s,;:-]+$"#)

    /// The first date written in the text, and the text once the date (and a "by", "on", "due"... just before it) is
    /// out, trimmed, with a capital first letter. "call accountant tomorrow" → ("Call accountant", tomorrow).
    static func parse(_ s: String, today t: String) -> (iso: String, text: String)? {
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let ns = s as NSString, all = NSRange(location: 0, length: ns.length)
        for (rx, f) in patterns {
            guard let m = rx.firstMatch(in: s, range: all) else { continue }
            let g: [String?] = (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i); return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            guard let iso = f(g, t), !iso.isEmpty else { continue }
            var a = m.range.location
            let b = m.range.location + m.range.length
            let head = ns.substring(to: a)
            if let p = leadIn.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length)) { a = p.range.location }
            var x = ns.substring(to: a) + " " + ns.substring(from: b)
            x = spaces.stringByReplacingMatches(in: x, range: NSRange(location: 0, length: (x as NSString).length), withTemplate: " ")
            x = beforePunct.stringByReplacingMatches(in: x, range: NSRange(location: 0, length: (x as NSString).length), withTemplate: "$1")
            x = ends.stringByReplacingMatches(in: x, range: NSRange(location: 0, length: (x as NSString).length), withTemplate: "")
            if x.isEmpty { x = s.trimmingCharacters(in: .whitespacesAndNewlines) }
            return (iso, capitalized(x))
        }
        return nil
    }
    static func capitalized(_ s: String) -> String { s.isEmpty ? s : s.prefix(1).uppercased() + s.dropFirst() }
}
