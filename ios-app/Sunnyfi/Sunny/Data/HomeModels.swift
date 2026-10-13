//
//  HomeModels.swift
//  Sunny
//
//  The Home payload, as `sunny-home` builds it into `home_snapshot` (one row,
//  rebuilt every 30 s). Snake-case keys decode with .convertFromSnakeCase;
//  anything the app does not use yet is simply not declared. Grows block by
//  block.
//

import Foundation

struct HomePayload: Decodable {
    let build: String
    let builtAt: String
    let today: String
    let tradingToday: Bool
    let calendar: [CalendarDay]
    let tradeTo415: [String]
    let fresh: Fresh
    let account: Account
    let indices: [Tape]
    let overnight: [Tape]
    let chart: Chart?
    let deck: Deck
    let lastWeek: LastWeek?
}

struct CalendarDay: Decodable, Hashable {
    let date: String
    let kind: String          // closed | early_close
    let closes: String?       // "13:00:00" on an early close
    let name: String
}

struct Fresh: Decodable {
    let marks: String?
    let quotes: String?
    let market: String?
    let trades: String?
    let accountClose: String?
}

struct Account: Decodable {
    let ok: Bool
    let value: Double?
    let today: Today?
    let marketValue: Double?
    let margin: Double?
    let cash: Double?
    let unrealized: Double?
    let timeValueSold: Double?
    let month: Period?
    let book: Period?
    let ibkrClose: IbkrClose?

    struct Today: Decodable { let amount: Double; let pct: Double?; let vs: String; let staleAnchor: Bool }
    struct Period: Decodable { let from: String; let realized: Double?; let commission: Double; let interest: Double }
    struct IbkrClose: Decodable { let date: String; let value: Double; let accounts: Int }
}

struct Tape: Decodable, Identifiable {
    var id: String { symbol }
    let symbol: String
    let label: String
    let state: String?
    let price: Double?
    let prevClose: Double?
    let changePct: Double?
    let change: Double?
    let pre: Double?
    let prePct: Double?
    let post: Double?
    let postPct: Double?
    let at: String?
}

struct LastWeek: Decodable {
    let weekStart: String
    let from: String
    let to: String
    let rows: [Row]
    let vix: Vix?
    struct Row: Decodable, Identifiable { var id: String { symbol }; let symbol: String; let changePct: Double?; let pricedMovePct: Double?; let close: Double? }
    struct Vix: Decodable { let close: Double; let changePct: Double? }
}

// MARK: - Account chart (block 02b)

struct Chart: Decodable {
    let from: String
    let to: String
    let lastClose: String?
    let liveLast: Bool
    let days: [String]
    let nav: [Double?]
    let margin: [Double?]
    let realizedCum: [Double?]
    let unrealized: [Double?]
    let timeValue: [Double?]
    let interestCum: [Double?]
    let commissionCum: [Double?]
    let dividendsCum: [Double?]
    let capitalLong: [Double?]
    let sharesValue: [Double?]
    let groups: [String: Group]
    let sharesTickers: [Int]
    let closed: [[Scalar]]
    let dividends: Dividends

    struct Group: Decodable { let line: [Double]; let real: [Double]; let unreal: [Double]; let tv: [Double] }
    struct Dividends: Decodable {
        let paid: [[Scalar]]
        /// [pay date, ticker] for each name that paid (02b "Payers").
        let payers: [[String]]?
        let yieldPct: Double?
        let next: Next?
        struct Next: Decodable { let ticker: String; let exDate: String; let payDate: String?; let amount: Double? }
    }
}

// MARK: - Deck (blocks 03-07)

struct Deck: Decodable {
    let earnings: [Earning]
    let season: Season?
    let reports: [Report]?
    let thetaChecks: [ThetaCheck]?

    struct Earning: Decodable, Identifiable {
        var id: String { ticker + date }
        let ticker: String
        let date: String
        let time: String?
        let estimated: Bool
        let callsOn: Int
        let putsOn: Int
        let shares: Double
        let exposure: Double
        let pricedMovePct: Double?
    }
    struct Season: Decodable {
        let quarter: String
        let starts: String
        let ends: String
        let showThrough: String
        let names: Int
        let last: String?
        let only: Only?
        struct Only: Decodable { let ticker: String; let date: String }
    }
    struct Report: Decodable { let kind: String; let label: String; let mark: String; let pending: String? }
    struct ThetaCheck: Decodable { let ticker: String; let leg: String; let trigger: String; let foundOn: String; let cardToday: Bool }
}

// MARK: - Mixed arrays ([date, group, flag, amount])

enum Scalar: Decodable {
    case s(String), n(Double), null
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Double.self) { self = .n(v) }
        else { self = .s(try c.decode(String.self)) }
    }
    var string: String? { if case .s(let v) = self { return v }; return nil }
    var number: Double? { if case .n(let v) = self { return v }; return nil }
}
