//
//  SampleBook.swift
//  Sunny
//
//  The design's sample book (handoff 6 Nov 2026, reference/sunny-web-data.js), ported as data for sample mode
//  (`-sample`, DEBUG). Tuesday Oct 27 close. Account a = Sunny (Nik), b = Nicolay (his cousin). Real books come
//  from the server in Pass 2 in the same shapes; nothing here reaches a release build's screens.
//

import Foundation

enum SampleBook {
    /// Price today and yesterday's close.
    static let q: [String: (Double, Double)] = [
        "SPY": (671.20, 668.52), "QQQ": (610.40, 606.81), "VIX": (16.40, 16.93), "BABA": (99.63, 101.77), "LULU": (99.05, 104.04),
        "NKE": (35.28, 35.90), "NFLX": (73.40, 72.10), "UBER": (67.10, 67.85), "FIS": (33.60, 33.95), "PEP": (141.20, 140.60),
        "MSFT": (512.30, 498.10), "GOOGL": (242.11, 236.40), "META": (731.20, 744.90), "AMD": (164.72, 158.05), "SHOP": (148.60, 141.22),
        "COST": (918.40, 925.10), "CRM": (244.80, 238.33), "PLTR": (178.20, 171.95), "DIS": (112.40, 115.02), "SBUX": (86.10, 83.70)]
    static let iv: [String: Double] = [
        "SPY": 0.15, "QQQ": 0.2, "VIX": 0.9, "BABA": 0.40, "LULU": 0.48, "NKE": 0.35, "NFLX": 0.45, "UBER": 0.38, "FIS": 0.30, "PEP": 0.18,
        "MSFT": 0.26, "GOOGL": 0.30, "META": 0.36, "AMD": 0.50, "SHOP": 0.55, "COST": 0.20, "CRM": 0.34, "PLTR": 0.65, "DIS": 0.28, "SBUX": 0.30]
    static let company: [String: String] = [
        "SPY": "S&P 500", "QQQ": "Nasdaq 100", "VIX": "Volatility", "BABA": "Alibaba", "LULU": "Lululemon", "NKE": "Nike", "NFLX": "Netflix",
        "UBER": "Uber", "FIS": "Fidelity National", "PEP": "PepsiCo", "MSFT": "Microsoft", "GOOGL": "Alphabet", "META": "Meta", "AMD": "AMD",
        "SHOP": "Shopify", "COST": "Costco", "CRM": "Salesforce", "PLTR": "Palantir", "DIS": "Disney", "SBUX": "Starbucks"]
    /// The book's names, the watchlist, the index cards.
    static let names = ["BABA", "LULU", "NKE", "NFLX", "UBER", "FIS", "PEP"]
    static let watch = ["MSFT", "GOOGL", "META", "AMD", "SHOP", "COST", "CRM", "PLTR", "DIS", "SBUX"]

    /// A sold leg: strike, call or put, contracts, sold at, now.
    struct Sold: Hashable { let k: Double; let put: Bool; let q: Int; let at: Double; let now: Double }
    /// A bought leg: kind (LEAPS, OTM calls, Insurance puts), strike, contracts, expiry label, paid.
    struct Bought: Hashable { let kind: Kind; let k: Double; let q: Int; let ex: String; let paid: Double
        enum Kind: String { case leaps = "LEAPS", otm = "OTM calls", ins = "Insurance puts" }
        var put: Bool { kind == .ins }
    }
    struct Name: Hashable { let strategy: String; let shares: Int; let avg: Double; let sold: [Sold]; let bought: [Bought]; let decay: Double }

    static func book(_ acct: String) -> [String: Name] { acct == "b" ? bookB : bookA }

    static let bookA: [String: Name] = [
        "BABA": Name(strategy: "Aftershock", shares: 1500, avg: 88.40, sold: [Sold(k: 104, put: false, q: 20, at: 0.66, now: 0.535)],
                     bought: [Bought(kind: .leaps, k: 100, q: 5, ex: "Jan ’28", paid: 26.40), Bought(kind: .otm, k: 108, q: 10, ex: "Sep ’27", paid: 11.20),
                              Bought(kind: .ins, k: 95, q: 5, ex: "Jan 15", paid: 4.90)], decay: 420),
        "LULU": Name(strategy: "Rebound", shares: 1000, avg: 118.20, sold: [],
                     bought: [Bought(kind: .leaps, k: 90, q: 10, ex: "Jan ’28", paid: 24.80), Bought(kind: .otm, k: 105, q: 6, ex: "Jun ’27", paid: 12.90),
                              Bought(kind: .ins, k: 90, q: 5, ex: "Jan 15", paid: 4.20)], decay: 390),
        "NKE": Name(strategy: "Ladder", shares: 6000, avg: 41.10, sold: [Sold(k: 36, put: false, q: 72, at: 0.32, now: 0.06), Sold(k: 34, put: true, q: 30, at: 0.18, now: 0.03)],
                    bought: [Bought(kind: .otm, k: 38, q: 20, ex: "Sep ’27", paid: 3.60), Bought(kind: .ins, k: 33, q: 30, ex: "Mar 19", paid: 1.45)], decay: 310),
        "NFLX": Name(strategy: "", shares: 2000, avg: 61.50, sold: [Sold(k: 74, put: false, q: 26, at: 0.55, now: 0.30)],
                     bought: [Bought(kind: .leaps, k: 65, q: 10, ex: "Jan ’28", paid: 19.20), Bought(kind: .otm, k: 80, q: 10, ex: "Jun ’27", paid: 8.40)], decay: 300),
        "UBER": Name(strategy: "", shares: 1200, avg: 72.30, sold: [Sold(k: 71, put: false, q: 12, at: 0.40, now: 0.28)], bought: [], decay: 0),
        "FIS": Name(strategy: "", shares: 2500, avg: 30.90, sold: [Sold(k: 35, put: false, q: 25, at: 0.20, now: 0.09)], bought: [], decay: 0),
        "PEP": Name(strategy: "", shares: 800, avg: 152.60, sold: [Sold(k: 145, put: false, q: 8, at: 0.70, now: 0.51)], bought: [], decay: 0)]

    static let bookB: [String: Name] = [
        "BABA": Name(strategy: "Aftershock", shares: 500, avg: 92.10, sold: [Sold(k: 104, put: false, q: 5, at: 0.66, now: 0.535)],
                     bought: [Bought(kind: .ins, k: 95, q: 2, ex: "Jan 15", paid: 4.90)], decay: 60),
        "LULU": Name(strategy: "Rebound", shares: 400, avg: 112.50, sold: [], bought: [Bought(kind: .otm, k: 105, q: 2, ex: "Jun ’27", paid: 12.90)], decay: 80),
        "NKE": Name(strategy: "Ladder", shares: 2000, avg: 39.80, sold: [Sold(k: 36, put: false, q: 20, at: 0.32, now: 0.06)],
                    bought: [Bought(kind: .ins, k: 33, q: 10, ex: "Mar 19", paid: 1.45)], decay: 70),
        "NFLX": Name(strategy: "", shares: 600, avg: 64.00, sold: [Sold(k: 74, put: false, q: 6, at: 0.55, now: 0.30)],
                     bought: [Bought(kind: .leaps, k: 65, q: 3, ex: "Jan ’28", paid: 19.20), Bought(kind: .otm, k: 80, q: 3, ex: "Jun ’27", paid: 8.40)], decay: 110),
        "UBER": Name(strategy: "", shares: 500, avg: 70.10, sold: [Sold(k: 71, put: false, q: 5, at: 0.40, now: 0.28)], bought: [], decay: 0),
        "FIS": Name(strategy: "", shares: 1000, avg: 31.20, sold: [Sold(k: 35, put: false, q: 10, at: 0.20, now: 0.09)], bought: [], decay: 0),
        "PEP": Name(strategy: "", shares: 300, avg: 150.10, sold: [Sold(k: 145, put: false, q: 3, at: 0.70, now: 0.51)], bought: [], decay: 0)]

    /// Calendar days from Tue Oct 27 to each long expiry.
    static let longDays: [String: Int] = ["Jan 15": 80, "Mar 19": 143, "Jun ’27": 234, "Sep ’27": 325, "Jan ’28": 451]
    /// Every chain on screen: label, calendar days left, weekly or monthly, trading days left.
    static let expiries: [(label: String, days: Int, kind: String, trading: Int)] = [
        ("Oct 30", 3, "Weekly", 5), ("Nov 6", 10, "Weekly", 10), ("Nov 13", 17, "Weekly", 15), ("Nov 20", 24, "Monthly", 20),
        ("Dec 18", 52, "Monthly", 40), ("Jan 15", 80, "Monthly", 59), ("Mar 19", 143, "Monthly", 102)]
    /// This week's sold legs expire Friday Oct 30, 3 calendar days on (and 3 trading days: Wed, Thu, Fri).
    static let fridayDays = 3
    static let fridayLabel = "Fri Oct 30"

    /// Dividends: per share, per quarter or year, next ex-date, days from Oct 27, pay date.
    static let dividends: [String: (ps: Double, per: String, ex: String, days: Int, pay: String)] = [
        "NKE": (0.41, "quarter", "Tue Dec 1", 35, "Mon Jan 4"), "PEP": (1.4225, "quarter", "Fri Dec 4", 38, "Wed Jan 6"),
        "FIS": (0.40, "quarter", "Tue Dec 8", 42, "Tue Dec 22"), "BABA": (1.05, "year", "Jun ’27", 225, "Jul ’27")]

    /// Walls per chain (expiry index): flip, ceiling, floor, accelerator, each (strike, confidence 1-3, gamma $M).
    typealias Wall = (k: Double, conf: Int, gamma: Double)
    static let chainWalls: [String: [(flip: Double, c: Wall?, f: Wall?, a: Wall?)]] = [
        "BABA": [(99.40, (104, 3, 12.4), nil, (99, 2, 9.8)), (99.1, (105, 2, 6.0), (96, 1, 3.1), (99, 2, 4.2)), (98.8, (105, 1, 3.8), (95, 1, 2.4), (98, 1, 2.0)),
                 (100.2, (110, 3, 15.2), (95, 2, 11.0), (99, 2, 6.4)), (98.5, (110, 2, 9.1), (90, 2, 7.7), (97, 1, 3.3)), (99.0, (110, 3, 18.6), (95, 3, 14.2), (97, 2, 8.8)),
                 (97.6, (115, 2, 8.4), (90, 2, 6.9), (95, 1, 2.6))],
        "LULU": [(91.5, (100, 3, 8.9), (95, 2, 6.1), nil), (92.0, (105, 2, 4.6), (95, 1, 3.0), nil), (92.5, (105, 1, 2.7), (92, 1, 1.9), nil),
                 (93.0, (110, 3, 12.0), (90, 2, 8.2), (92.5, 1, 3.5)), (94.0, (110, 2, 7.4), (85, 2, 6.0), (92.5, 2, 4.8)), (93.5, (110, 3, 13.5), (90, 3, 10.1), (92.5, 2, 5.2)),
                 (92.0, (120, 2, 6.8), (80, 1, 4.4), (90, 1, 2.2))],
        "NKE": [(33.8, (36, 3, 6.3), (34, 2, 5.4), (33.5, 1, 3.2)), (33.9, (37, 2, 3.4), (34, 1, 2.2), (33.5, 1, 1.6)), (33.6, (37.5, 1, 2.1), (33, 1, 1.5), nil),
                (34.2, (38, 3, 9.8), (33, 2, 6.6), (34, 2, 4.0)), (33.5, (40, 2, 5.9), (32, 2, 4.8), (33, 1, 2.0)), (33.7, (40, 3, 11.2), (32, 3, 8.5), (33, 1, 3.1)),
                (33.0, (42, 2, 6.1), (30, 2, 5.0), nil)]]

    /// A name's chain walls; names without hand-drawn walls scale Nike's to their price (as the design does).
    static func walls(_ t: String, _ e: Int) -> (flip: Double, c: Wall?, f: Wall?, a: Wall?) {
        if let w = chainWalls[t]?[e] { return w }
        let px = q[t]?.0 ?? 35.28, r = px / 35.28, z = px < 50 ? 0.5 : px < 200 ? 1 : 5
        let sc: (Wall?) -> Wall? = { w in w.map { ((($0.k * r / z).rounded() * z * 100).rounded() / 100, $0.conf, ($0.gamma * r * 10).rounded() / 10) } }
        let n = chainWalls["NKE"]![e]
        var a = sc(n.a); let f = sc(n.f)
        if let aa = a, let ff = f, aa.k == ff.k { a = nil }
        return ((n.flip * r * 100).rounded() / 100, sc(n.c), f, a)
    }

    /// To do orders (Tomorrow's orders, Overview To do): name, what, expiry, the picked way, credit or cost.
    struct Order: Hashable { let t: String; let what: String; let ex: String; let why: String; let wall: String; let act: String; let amount: Double; let cost: Bool }
    static func orders(_ acct: String) -> [Order] {
        if acct == "b" {
            return [Order(t: "LULU", what: "Sell calls", ex: "Oct 30", why: "One per 100 shares, at the money on the next strike", wall: "Wall 100 ●●●", act: "Sell 4 Oct 30 100 calls", amount: 580, cost: false)]
        }
        return [
            Order(t: "BABA", what: "Buy calls", ex: "Sep ’27", why: "OTM calls 5 to 10% out, 7 to 12 months: the plan wants 13, you hold 10", wall: "8.4% out", act: "Buy 3 Sep ’27 108 calls", amount: 3510, cost: true),
            Order(t: "BABA", what: "Sell puts", ex: "Oct 30", why: "From the put cap, at the rule’s strike", wall: "Wall 98 ●●●", act: "Sell 5 Oct 30 98 puts", amount: 260, cost: false),
            Order(t: "LULU", what: "Sell calls", ex: "Oct 30", why: "One per 100 shares, at the money on the next strike", wall: "Wall 100 ●●●", act: "Sell 10 Oct 30 100 calls", amount: 1450, cost: false),
            Order(t: "LULU", what: "Sell puts", ex: "Oct 30", why: "From the put cap, at the rule’s strike", wall: "Wall 95 ●●○", act: "Sell 5 Oct 30 95 puts", amount: 410, cost: false)]
    }

    /// The account value and today's move shown on each Home chart (sample only; the app reads IBKR).
    static let account: [String: (value: Double, prev: Double)] = ["a": (92000, 90760), "b": (33120, 32674)]
}
