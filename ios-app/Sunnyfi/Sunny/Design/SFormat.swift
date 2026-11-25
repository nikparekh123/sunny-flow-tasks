//
//  SFormat.swift
//  Sunny
//
//  How every number reads (README Rules, block 23 "Money"):
//  · The focus look (handoff 2026-11-25-focus §2.2): colour no longer carries the sign. A gain or loss that
//    colour used to mark takes + or − (U+2212) in front (SF.signed); the formatters here stay unsigned.
//  · $ with K above $1,000, one decimal, ".0" dropped: $4.2K, $22K, $860.
//    Above $100,000 the K loses its decimal ($176K); millions read $1.2M.
//  · A comparison carries its sign: "+$1.2K" for a gain, "−$1.2K" for a loss.
//

import Foundation

enum F {
    /// $92,000 — the account value and other full figures, no sign.
    static func money(_ v: Double, cents: Bool = false) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.minimumFractionDigits = cents ? 2 : 0
        n.maximumFractionDigits = cents ? 2 : 0
        return "$" + (n.string(from: NSNumber(value: abs(v))) ?? "0")
    }

    /// $4.2K · $22K · $860 · $176K · $1.2M, no sign.
    static func moneyK(_ v: Double) -> String {
        let a = abs(v)
        if a < 1_000 { return "$" + String(Int(a.rounded())) }
        if a < 100_000 { return "$" + trim(a / 1_000) + "K" }
        if a < 1_000_000 { return "$" + String(Int((a / 1_000).rounded())) + "K" }
        return "$" + trim(a / 1_000_000) + "M"
    }

    /// A comparison: "+$1.2K" for a gain, "−$1.2K" for a loss (focus: red no longer says it).
    static func moneyDelta(_ v: Double) -> String { SF.signed(v, moneyK(v)) }

    /// 2.13% · 1.4% — no sign; `places` decimals.
    static func pct(_ v: Double, places: Int = 2) -> String {
        String(format: "%.\(places)f%%", abs(v))
    }

    /// One decimal with ".0" dropped.
    static func trim(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    /// 16.42 — a level (VIX), no $ and no sign.
    static func level(_ v: Double, places: Int = 2) -> String { String(format: "%.\(places)f", abs(v)) }

    /// "Oct 9", "Sep 28" from yyyy-MM-dd.
    static func day(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return iso }
        let m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][max(0, min(11, p[1] - 1))]
        return "\(m) \(p[2])"
    }
}
