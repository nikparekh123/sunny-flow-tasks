//
//  Formatting.swift
//  Sunnyfi
//
//  Shared number / time formatters — Swift ports of fmtMoney / fmtK /
//  fmtPct / fmtGreek from src/portfolio/data.ts. Kept module-level so
//  every screen renders numbers the same way.
//

import Foundation

/// "$642,830" / "−$1,234" / "+$1,234" with sign control.
func fmtMoney(_ v: Double, sign: Bool = false) -> String {
    let a = Int(abs(v).rounded())
    let s: String
    if sign {
        s = v > 0 ? "+" : v < 0 ? "−" : ""
    } else {
        s = v < 0 ? "−" : ""
    }
    return s + "$" + a.formatted(.number.grouping(.automatic))
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

/// "+1.23%" / "−0.45%"
func fmtPct(_ v: Double) -> String {
    let s = v > 0 ? "+" : v < 0 ? "−" : ""
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
