//
//  TickerNames.swift
//  Sunnyfi
//
//  Fallback ticker → display-name map for tickers in the book.
//  Lets the Company header read "Adobe" big when positions.name is
//  null on the broker import. Edit freely as new tickers come in.
//

import Foundation

enum TickerNames {
    static let map: [String: String] = [
        // Current holdings (per the May 31 lot import)
        "ADBE": "Adobe",
        "BBY":  "Best Buy",
        "FIG":  "Figma",
        "HOOD": "Robinhood",
        "INTU": "Intuit",
        "LULU": "Lululemon",
        "META": "Meta Platforms",
        "NFLX": "Netflix",
        "NKE":  "Nike",
        "PYPL": "PayPal",
        "WDAY": "Workday",

        // Other commonly-referenced tickers
        "AAPL": "Apple",
        "NVDA": "NVIDIA",
        "CRM":  "Salesforce",
        "TEAM": "Atlassian",
        "FSRNQ":"Fisker",
        "MSFT": "Microsoft",
        "GOOG": "Alphabet",
        "GOOGL":"Alphabet",
        "AMZN": "Amazon",
        "TSLA": "Tesla",
    ]

    /// Returns the display name for `ticker` (uppercased input). Falls
    /// back to nil so the caller can decide what to render.
    static func name(for ticker: String) -> String? {
        map[ticker.uppercased()]
    }
}
