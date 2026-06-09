//
//  IVMath.swift
//  Sunnyfi
//
//  Pure math + zone helpers for the IV Seller Score model.
//  Mirrors the React prototype in design_handoff_iv_volatility/
//  (see README.md for the spec).
//
//  Three metrics, derived from a single TickerIVRow:
//    • IVR    = (current_iv − iv_low) / (iv_high − iv_low) × 100
//    • Spread = current_iv − hv30, in IV points
//    • Score  = IVR × 0.6 + normSpread × 0.4
//      where normSpread = clamp(spread / 0.20 × 100, 0, 100)
//      (i.e. +20 IV pts of spread → 100, 0 or below → 0, linear).
//
//  Verdict tags are score-driven, with a CAUTION overlay when IVR
//  ≥ 80 (extreme vol → catalyst risk regardless of score).
//

import Foundation
import SwiftUI

// MARK: - Row → primitives

enum IVMath {

    /// IVR (0–100). Returns nil if the window is degenerate
    /// (low == high) — typically just-seeded ticker with one snapshot.
    static func ivr(_ row: TickerIVRow) -> Double? {
        guard let now = row.current_iv,
              let lo = row.iv_low,
              let hi = row.iv_high,
              hi > lo
        else { return nil }
        let v = (now - lo) / (hi - lo) * 100
        return min(100, max(0, v))
    }

    /// Spread = current_iv − hv30, in IV percentage points
    /// (i.e. decimal 0.03 = +3 IV pts).
    static func spread(_ row: TickerIVRow) -> Double? {
        guard let now = row.current_iv, let hv = row.current_hv30 else { return nil }
        return now - hv
    }

    /// Normalized spread → 0–100. +20 IV pts (decimal 0.20) caps at 100.
    static func normSpread(_ row: TickerIVRow) -> Double? {
        guard let s = spread(row) else { return nil }
        return min(100, max(0, s / 0.20 * 100))
    }

    /// Composite Seller Score (0–100). Returns nil if either IVR
    /// or normSpread can't be computed (then we have nothing to show).
    static func sellerScore(_ row: TickerIVRow) -> Double? {
        guard let r = ivr(row), let ns = normSpread(row) else { return nil }
        return r * 0.6 + ns * 0.4
    }

    // MARK: - Verdict zones

    /// Score-driven verdict with a CAUTION overlay on extreme IVR.
    /// Matches the README's `if/else if` ladder exactly.
    enum ScoreZone: String, Sendable {
        case caution, sell, neutral, light, hold

        var label: String {
            switch self {
            case .caution: return "CAUTION"
            case .sell:    return "SELL"
            case .neutral: return "NEUTRAL"
            case .light:   return "LIGHT"
            case .hold:    return "HOLD"
            }
        }

        var reading: String {
            switch self {
            case .caution: return "Extreme vol — confirm the catalyst first."
            case .sell:    return "Rich vol, spread confirms — prime for income."
            case .neutral: return "Fair vol — normal cadence."
            case .light:   return "Below average — wide strikes only."
            case .hold:    return "Cheap vol — hold off."
            }
        }
    }

    static func scoreZone(_ row: TickerIVRow) -> ScoreZone? {
        guard let r = ivr(row), let s = sellerScore(row) else { return nil }
        if r >= 80   { return .caution }
        if s >= 70   { return .sell }
        if s >= 45   { return .neutral }
        if s >= 25   { return .light }
        return .hold
    }

    // MARK: - Standalone IVR + Spread zones (Two-cards layout)

    enum IVRZone: String, Sendable {
        case caution, sell, neutral, light, hold

        var label: String {
            switch self {
            case .caution: return "CAUTION"
            case .sell:    return "SELL"
            case .neutral: return "NEUTRAL"
            case .light:   return "LIGHT"
            case .hold:    return "HOLD"
            }
        }
    }

    static func ivrZone(_ row: TickerIVRow) -> IVRZone? {
        guard let r = ivr(row) else { return nil }
        if r >= 80 { return .caution }
        if r >= 60 { return .sell }
        if r >= 40 { return .neutral }
        if r >= 20 { return .light }
        return .hold
    }

    enum SpreadZone: String, Sendable {
        case overpaid, rich, fair, danger

        var label: String {
            switch self {
            case .overpaid: return "OVERPAID"
            case .rich:     return "RICH"
            case .fair:     return "FAIR"
            case .danger:   return "DANGER"
            }
        }
    }

    static func spreadZone(_ row: TickerIVRow) -> SpreadZone? {
        guard let s = spread(row) else { return nil }
        // Thresholds in IV percentage points (decimal).
        if s > 0.15  { return .overpaid }
        if s >= 0.05 { return .rich }
        if s >= 0    { return .fair }
        return .danger
    }

    // MARK: - Number-color tones (reserve color for actionable extremes)

    /// IVR / Score number color rule from the spec:
    /// IVR ≥ 80 → warn, else score ≥ 70 (or IVR ≥ 60 standalone) → neon, else default ink.
    static func scoreTone(_ row: TickerIVRow) -> TodayTone {
        guard let r = ivr(row), let s = sellerScore(row) else { return .neutral }
        if r >= 80 { return .warn }
        if s >= 70 { return .neon }
        return .neutral
    }

    static func ivrTone(_ row: TickerIVRow) -> TodayTone {
        guard let r = ivr(row) else { return .neutral }
        if r >= 80 { return .warn }
        if r >= 60 { return .neon }
        return .neutral
    }

    static func spreadTone(_ row: TickerIVRow) -> TodayTone {
        guard let s = spread(row) else { return .neutral }
        if s > 0.10 { return .pos }
        if s < 0    { return .neg }
        return .neutral
    }
}

// MARK: - Verdict chip color helper

extension Color {
    /// Background + foreground for a verdict action chip.
    /// Matches the README chip-color table.
    static func ivChipColors(forScore zone: IVMath.ScoreZone) -> (bg: Color, fg: Color) {
        switch zone {
        case .sell:    return (.theme.neon, .white)
        case .caution: return (.theme.ivAmber, Color(hex: 0x1d2a09))
        case .neutral, .light, .hold:
            return (.theme.tintMuted, .theme.fg3)
        }
    }

    static func ivChipColors(forIVR zone: IVMath.IVRZone) -> (bg: Color, fg: Color) {
        switch zone {
        case .sell:    return (.theme.neon, .white)
        case .caution: return (.theme.ivAmber, Color(hex: 0x1d2a09))
        case .neutral, .light, .hold:
            return (.theme.tintMuted, .theme.fg3)
        }
    }

    static func ivChipColors(forSpread zone: IVMath.SpreadZone) -> (bg: Color, fg: Color) {
        switch zone {
        case .overpaid: return (.theme.neon, .white)
        case .rich:     return (.theme.tintPos, .theme.pos)
        case .danger:   return (.theme.neg, .white)
        case .fair:     return (.theme.tintMuted, .theme.fg3)
        }
    }
}
