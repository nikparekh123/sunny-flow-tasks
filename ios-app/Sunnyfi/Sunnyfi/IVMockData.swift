//
//  IVMockData.swift
//  Sunnyfi
//
//  TEMPORARY — DEBUG-only seed data so we can audit the IV section's
//  UI against the design handoff without waiting on the daily
//  ticker-iv-snapshot cron + Polygon round-trip.
//
//  Values exactly mirror design_handoff_iv_volatility/home-data.jsx
//  → IV_DATA. INTU is tuned to score 83 (SELL); COIN to 93 (CAUTION);
//  AAPL/COST to ~10 (HOLD). That lets us verify every verdict-chip
//  color, every gauge segment marker position, every score-tone color
//  in one render.
//
//  Decimal convention (matches TickerIVRow): atm_iv 0.42 == 42%,
//  hv30 0.31 == 31%.
//
//  Remove this file (and the seed call in PortfolioStore.fetchAll)
//  once ticker_iv_summary returns live data.
//

#if DEBUG
import Foundation

enum IVMockData {
    /// The 9 tunable rows from the design prototype. iv_window_days
    /// is set to 252 so the UI labels them "252d range" (close to a
    /// full year) which matches the design's "52w range" framing.
    static let rows: [TickerIVRow] = [
        TickerIVRow(ticker: "INTU",
                    current_iv: 0.64, current_hv30: 0.41,
                    iv_low: 0.38, iv_high: 0.74, iv_window_days: 252,
                    last_snapshot_date: "2026-06-09", window_start: "2025-06-09"),
        TickerIVRow(ticker: "CRM",
                    current_iv: 0.69, current_hv30: 0.44,
                    iv_low: 0.41, iv_high: 0.78, iv_window_days: 252,
                    last_snapshot_date: "2026-06-09", window_start: "2025-06-09"),
        TickerIVRow(ticker: "COIN",
                    current_iv: 0.94, current_hv30: 0.71,
                    iv_low: 0.52, iv_high: 0.99, iv_window_days: 252,
                    last_snapshot_date: "2026-06-09", window_start: "2025-06-09"),
        TickerIVRow(ticker: "AMD",
                    current_iv: 0.62, current_hv30: 0.38,
                    iv_low: 0.40, iv_high: 0.80, iv_window_days: 252,
                    last_snapshot_date: "2026-06-09", window_start: "2025-06-09"),
        TickerIVRow(ticker: "TSLA",
                    current_iv: 0.71, current_hv30: 0.49,
                    iv_low: 0.45, iv_high: 0.95, iv_window_days: 252,
                    last_snapshot_date: "2026-06-09", window_start: "2025-06-09"),
        TickerIVRow(ticker: "MSFT",
                    current_iv: 0.33, current_hv30: 0.26,
                    iv_low: 0.24, iv_high: 0.49, iv_window_days: 252,
                    last_snapshot_date: "2026-06-09", window_start: "2025-06-09"),
        TickerIVRow(ticker: "NVDA",
                    current_iv: 0.58, current_hv30: 0.52,
                    iv_low: 0.42, iv_high: 0.88, iv_window_days: 252,
                    last_snapshot_date: "2026-06-09", window_start: "2025-06-09"),
        TickerIVRow(ticker: "AAPL",
                    current_iv: 0.28, current_hv30: 0.31,
                    iv_low: 0.22, iv_high: 0.55, iv_window_days: 252,
                    last_snapshot_date: "2026-06-09", window_start: "2025-06-09"),
        TickerIVRow(ticker: "COST",
                    current_iv: 0.22, current_hv30: 0.25,
                    iv_low: 0.18, iv_high: 0.42, iv_window_days: 252,
                    last_snapshot_date: "2026-06-09", window_start: "2025-06-09"),
    ]
}
#endif
