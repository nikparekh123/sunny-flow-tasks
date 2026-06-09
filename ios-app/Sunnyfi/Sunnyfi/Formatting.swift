//
//  Formatting.swift
//  Sunnyfi
//
//  Shared number / time formatters — Swift ports of fmtMoney / fmtK /
//  fmtPct / fmtGreek from src/portfolio/data.ts. Kept module-level so
//  every screen renders numbers the same way.
//

import Foundation

/// "$642,830" / "−$1,234" / "+$1,234" with sign control. Pass
/// `decimals > 0` for prices that need fractional digits (e.g. spot).
func fmtMoney(_ v: Double, sign: Bool = false, decimals: Int = 0) -> String {
    let absV = abs(v)
    let s: String
    if sign {
        s = v > 0 ? "+" : v < 0 ? "−" : ""
    } else {
        s = v < 0 ? "−" : ""
    }
    if decimals > 0 {
        let formatted = absV.formatted(
            .number
                .precision(.fractionLength(decimals))
                .grouping(.automatic)
        )
        return s + "$" + formatted
    }
    return s + "$" + Int(absV.rounded()).formatted(.number.grouping(.automatic))
}

/// "+$2.3k" / "−$420" — compact for ticker rows / KPI cells.
func fmtK(_ v: Double) -> String {
    let sign = v < 0 ? "−" : "+"
    let a = abs(v)
    if a >= 1000 {
        let scaled = a / 1000
        let digits = a >= 10_000 ? 0 : 1
        return "\(sign)$\(String(format: "%.\(digits)f", scaled))k"
    }
    return "\(sign)$\(Int(a.rounded()).formatted(.number.grouping(.automatic)))"
}

/// "↑1.23%" / "↓0.45%" / "0.00%" — arrow glyph carries the sign so
/// the reader gets directionality at the same scale as the number.
/// Replaces the old `+`/`−` prefix style per the design system
/// (Handoff §1).
func fmtPct(_ v: Double) -> String {
    let s = v > 0 ? "↑" : v < 0 ? "↓" : ""
    return s + String(format: "%.2f", abs(v)) + "%"
}

/// Greeks — rounded to whole-share equivalents (per data.ts).
func fmtGreek(_ v: Double) -> String {
    let sign = v > 0 ? "+" : v < 0 ? "−" : ""
    return sign + Int(abs(v).rounded()).formatted(.number.grouping(.automatic))
}

/// "9:41 AM"
func fmtTime(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f.string(from: d)
}

/// Option strike — drop trailing decimals when whole. Many tickers
/// have half-dollar strikes (e.g. PYPL 27.5, HOOD 56.5); using
/// `Int(strike)` everywhere was silently truncating them. Examples:
///   100    → "100"
///    27.5  → "27.5"
///    27.55 → "27.55"
func fmtStrike(_ value: Double) -> String {
    let rounded = (value * 100).rounded() / 100
    if rounded == rounded.rounded() {
        return String(format: "%.0f", rounded)
    }
    // One decimal when the second is zero (e.g. 27.5), else two.
    if (rounded * 10).rounded() / 10 == rounded {
        return String(format: "%.1f", rounded)
    }
    return String(format: "%.2f", rounded)
}
