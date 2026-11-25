//
//  BriefCore.swift
//  Sunny
//
//  New Home and Positions (handoff 6 Nov 2026, blocks 29 to 34). The moment Home is in, the account on
//  screen, privacy, and the debug switches that pin each state for screenshots.
//
//  ⚠ THE MOMENT COMES FROM THE NEW YORK CLOCK (README 5, design answers 1 and 3, 6 Nov 2026):
//    Mon-Fri 4:00 to 9:30 Pre-market · 9:30 to 9:35 the Bell · to 3:40 PM Market hours · to 3:55 Last 20
//    · to 4:00 Last 5 · 4:00 to 8:00 PM Post-market (Mon-Thu) · 8:00 PM to 4:00 AM the overnight Futures
//    summary. Friday 4:00 PM to Sunday 6:00 PM Week in Review; Sunday 6:00 PM, when futures open, the
//    overnight summary takes over until Monday 4:00 AM.
//

import SwiftUI
import Observation

// MARK: - The moment

enum Moment: String, CaseIterable, Identifiable {
    case futures, pre, bell, open, last20, last5, post, weekend
    var id: String { rawValue }

    /// The brief's title (block 29).
    var title: String {
        switch self {
        case .futures, .pre: "Pre-market Summary"
        case .bell, .open, .last20, .last5: "Market Hours"
        case .post: "Post-market Summary"
        case .weekend: "Week in Review"
        }
    }

    /// The regular session is open (live prices, What's moving, To decide).
    var isSession: Bool { [.bell, .open, .last20, .last5].contains(self) }

    /// `close` = that day's close in New York minutes: 960 (4:00 PM), or 780 on an early close (the last 20 and 5 minutes
    /// and post-market follow it, as "Post-market takes over at 1:00 PM" says). Same rule as sunny-home `momentOf`.
    /// `closedToday`: a market holiday on a weekday, a day off like Saturday (Nik, 8 Nov 2026). `nextTomorrow`: the next
    /// session is tomorrow, so futures open at 6:00 PM (not the night before a holiday). Same rule as sunny-home `momentOf`.
    static func at(_ date: Date, close: Int = 960, closedToday: Bool = false, nextTomorrow: Bool = true) -> Moment {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        let wd = c.weekday ?? 2, m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if wd == 7 { return .weekend }                                                       // Saturday
        if wd == 1 || closedToday { return m >= 18 * 60 && nextTomorrow ? .futures : .weekend }  // Sunday, a holiday
        if wd == 6 && m >= close { return .weekend }              // Friday after the close
        switch m {
        case ..<(4 * 60): return .futures
        case ..<(9 * 60 + 30): return .pre
        case ..<(9 * 60 + 35): return .bell
        case ..<(close - 20): return .open
        case ..<(close - 5): return .last20
        case ..<close: return .last5
        case ..<(20 * 60): return .post
        default: return nextTomorrow ? .futures : .weekend    // the night before a holiday is a day off
        }
    }
}

// MARK: - Accounts

/// The account strip (handoff 2026-11-24 §2.2): Together · Sunny · Nicolay for an owner of every book, Together first
/// (it replaces Overview); a login with one book sees no strip. Together is book T on the server, every account added
/// up (Nik, 24 Nov 2026: "the default view for me will always be Together"). Names never "Niket" or "N" (answer 13).
enum BriefAccount: String, CaseIterable, Identifiable, Hashable {
    case together, sunny, nicolay
    var id: String { rawValue }
    var name: String {
        switch self { case .together: "Together"; case .sunny: "Sunny"; case .nicolay: "Nicolay" }
    }
    /// The server's book: T, S or N.
    var book: String {
        switch self { case .together: "T"; case .sunny: "S"; case .nicolay: "N" }
    }
    init?(book: String?) {
        switch book { case "T": self = .together; case "S": self = .sunny; case "N": self = .nicolay; default: return nil }
    }
    /// "Sunny’s book", "Sunny and Nicolay’s book" (Together, the design's title).
    var bookTitle: String { self == .together ? "Sunny and Nicolay’s book" : "\(name)’s book" }
    /// The sample book's key (sunny-web-data.js: a = Nik, b = his cousin).
    var sampleKey: String { self == .nicolay ? "b" : "a" }
}

// MARK: - Debug switches (DEBUG simulator only)

/// `-sample` reads the design's sample book (Brief/Sample/*.json) instead of the server, so every screen can
/// be checked against the handoff before real data goes in (README 2, Pass 1). With it:
///   -moment pre|open|post|weekend|futures|bell|last20|last5   pins the moment (else `-now` or the clock)
///   -acct together|sunny|nicolay                              the account on screen
///   -privacy                                                  privacy on
///   -tab positions|income                                     opens on Positions or Income
///   -pname NKE                                                Positions on that name
enum BriefDebug {
    static let sample: Bool = flag("-sample")
    static let moment: Moment? = value("-moment").flatMap(Moment.init(rawValue:))
    static let account: BriefAccount? = value("-acct").flatMap(BriefAccount.init(rawValue:))
    static let privacy: Bool = flag("-privacy")
    static let tab: String? = value("-tab")
    static let name: String? = value("-pname")
    static let scroll: CGFloat? = value("-scroll").flatMap(Double.init).map { CGFloat($0) }
    static let stop: Int? = value("-pstop").flatMap(Int.init)
    /// `-open timevalue|economy|ticker:NFLX` opens an overlay at launch.
    static let open: String? = value("-bopen")
    /// `-pin pre` or `-pin open:week` (moment, then holiday week | early): the debug menu's pin, applied at launch.
    static let pin: BriefPin? = value("-pin").flatMap { s in
        let p = s.split(separator: ":").map(String.init)
        return Moment(rawValue: p[0]).map { BriefPin(moment: $0, holiday: p.count > 1 ? p[1] : nil) }
    }

    private static func flag(_ k: String) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains(k)
        #else
        return false
        #endif
    }
    private static func value(_ k: String) -> String? {
        #if DEBUG && targetEnvironment(simulator)
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: k), i + 1 < a.count else { return nil }
        return a[i + 1]
        #else
        return nil
        #endif
    }
}

enum BriefSheetKind: String, Identifiable { case timeValue, economy, todo; var id: String { rawValue } }

// MARK: - State shared by Home and Positions

@MainActor
@Observable
final class BriefState {
    /// The accounts this login sees, strip order. One account: no strip.
    var accounts: [BriefAccount] = [.sunny]
    var account: BriefAccount = .sunny
    /// The direction of the last switch, for the 28 pt slide (block 33).
    var switchDir: CGFloat = 0
    /// Positions: the name to open on (from Your position).
    var positionsName: String?
    /// Overlays (block 33): the Time value sheet, the economy sheet, a ticker chart pushed from a name tile.
    var sheet: BriefSheetKind?
    var ticker: String?
    /// Activity (round 161a): the page from the bell, and the payload's events for the bell and the Levels card.
    var activityOpen = false
    var activity: JSONValue?
    var today = ""

    /// The server's brief for the book on screen, decoded once per update (memoized: never built in a body).
    private(set) var live: BriefLive?
    private var liveKey: String?
    /// The legs the brief was priced on (payload.brief_inputs), for Positions: set with each new build.
    private(set) var inputs: JSONValue?
    /// The book the brief is for ("T", "S", "N") and its build: Positions asks sunny-positions for that book.
    private(set) var book: String?
    var built: String? { liveKey }
    /// Positions on the real book: one model per name and build, fetched when a name opens.
    let positions = PositionsSource()

    /// Together's split (payload.split): each account's value and today, for the line under the account value.
    private(set) var split: [(name: String, value: Double, today: Double)] = []
    /// payload.split as it comes (Together only): [{id, name, value, today, pct, chart, open_pl, margin, tvLeft, heads
    /// {kicker: "$13.7K"}, names [tickers], parts, nameParts}].
    private(set) var splitRaw: JSONValue?
    /// payload.income (24 Nov 2026): the Income tab and Income today read it.
    private(set) var income: JSONValue?
    /// payload.income in the words Income today and the Income tab draw, built once per build (never in a body).
    private(set) var incomeModel: IncModel?
    private var incomeKey: String?
    func setIncome(_ j: JSONValue?, key: String) {
        guard key != incomeKey else { return }
        incomeKey = key
        income = j
        incomeModel = IncModel.build(j)
    }

    // MARK: Pinned (the debug menu, Pass 3)
    /// A moment pinned from the debug menu: its page replaces the live one until Back to live.
    private(set) var pin: BriefPin?
    /// The pinned New York day and minute: the day card's sky and clock follow it.
    private(set) var pinnedAt: Date?
    var pinLoading = false
    var pinError: String?
    var debugOpen = false
    /// The live brief kept aside while a moment is pinned (new builds keep landing here).
    private var realLive: BriefLive?
    /// The time the brief screens draw: the pinned one, else the app's clock.
    func now() -> Date { pinnedAt ?? SClock.now() }
    func setPinned(_ p: BriefPin, live l: BriefLive, at: Date?) {
        if pin == nil { realLive = live }
        pin = p; pinnedAt = at; live = l
    }
    func unpin() {
        guard pin != nil else { return }
        live = realLive; realLive = nil; pin = nil; pinnedAt = nil
    }

    /// When the book's prices and IBKR's trades last landed (payload.fresh), for README 9.4's "IBKR down" state.
    var fresh: (marks: Date?, trades: Date?) = (nil, nil)
    /// Before the open and after the close: prices are estimates from pre-market ("pre") or after-hours ("post")
    /// trades, newest at `at` (payload.prices_est, 18 Nov 2026). Nil in the session.
    var est: (session: String, at: Date?)? = nil
    /// README 9.4: IBKR down in market hours (prices over 10 min old or trades over 20): Positions shows the last
    /// values "As of 3:58 PM" and no makes-the-most line. Nil while the data is fresh, outside the session, or pinned.
    func asOf() -> Date? {
        guard pin == nil, moment().isSession else { return nil }
        let t = now()
        let late = (fresh.marks.map { t.timeIntervalSince($0) > 600 } ?? true) || (fresh.trades.map { t.timeIntervalSince($0) > 1200 } ?? true)
        return late ? (fresh.marks ?? fresh.trades) : nil
    }

    private var debugAccountApplied = false

    func ingest(_ brief: JSONValue?, key: String?, book: String? = nil, books: [String] = [], inputs: JSONValue? = nil,
                split: JSONValue? = nil) {
        guard key != liveKey || book != self.book else { return }
        liveKey = key
        self.book = book
        self.inputs = inputs
        self.split = (split?.array ?? []).compactMap { p in
            guard let n = p["name"].string, let v = p["value"].double else { return nil }
            return (n, v, p["today"].double ?? 0)
        }
        self.splitRaw = split
        if !BriefDebug.sample {
            // The strip on the real books: Together first, then Sunny before Nicolay (Nik, 8 and 24 Nov 2026), whatever
            // order the memberships come in.
            accounts = BriefAccount.allCases.filter { books.contains($0.book) }
            account = BriefAccount(book: book) ?? .sunny
            if accounts.isEmpty { accounts = [account] }
            // A test run's -acct opens that account once the real books are in (simulator only).
            if let a = BriefDebug.account, !debugAccountApplied, accounts.contains(a) { account = a; debugAccountApplied = true }
        }
        #if DEBUG && targetEnvironment(simulator)
        let t0 = CFAbsoluteTimeGetCurrent()
        #endif
        let decoded = brief.map(BriefLive.init)
        #if DEBUG && targetEnvironment(simulator)
        print("SUNNY-PERF ingest \(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)) ms")
        #endif
        if pin != nil { realLive = decoded } else { live = decoded }
    }

    var showsStrip: Bool { accounts.count > 1 }

    func pick(_ a: BriefAccount) {
        guard a != account, accounts.contains(a) else { return }
        let from = accounts.firstIndex(of: account) ?? 0, to = accounts.firstIndex(of: a) ?? 0
        switchDir = to > from ? 1 : -1
        // A pinned page is one book's: switching book drops the pin.
        if pin != nil { unpin() }
        account = a
    }

    /// The moment on screen: pinned in a debug run, else the New York clock.
    /// The exchange calendar (closed days, early closes), set with each Home build.
    var calendar: [CalendarDay] = []
    func moment(at date: Date? = nil) -> Moment {
        if let m = pin?.moment ?? BriefDebug.moment { return m }
        let d = date ?? now(), t = MarketClock.ny(d)
        let tomorrow = MarketClock.ny(d.addingTimeInterval(86_400))
        let closedToday = t.weekday >= 2 && t.weekday <= 6 && !MarketClock.isTradingDay(t.date, weekday: t.weekday, calendar)
        return Moment.at(d, close: MarketClock.closeMinutes(t.date, calendar), closedToday: closedToday,
                         nextTomorrow: MarketClock.isTradingDay(tomorrow.date, weekday: tomorrow.weekday, calendar))
    }
}

/// Privacy (block 33): the eye beside the account value. One switch, kept on the phone, shared with Siri's
/// "Hide Sunny numbers" (answer 18), so it is the same key the account block already used.
enum BriefPrivacy {
    static let key = "sunny.hideNumbers"
}
