//
//  SDSale.swift
//  Sunny
//
//  What the sale does (handoff 2026-11-11-sd-whatif-totals 1.6 and 1.9, App Explorations 143a): Held, + New and
//  = Both at the chosen expiry, each with its chance of profit, its breakevens and where it profits or loses.
//
//  ⚠ PORTED LINE FOR LINE FROM supabase/functions/_shared/sd-engine.ts (N, bs, cdfOf, sale), so the app and the web
//  give the same numbers for the same picks. Change it there first. Checked 11 Nov 2026 against sd-engine.ts (with the
//  breakevens found from the top of the hill) on the NKE reply: Nov 20, 10 calls at 40 and 5 puts at 35, Held 74.4% /
//  $4.6K / call BE 41.42 / put BE 34.85, New 80.3% / $913, Both 75.2% / $5.5K / 41.34 / 34.66; Nov 13, Held 83.3% /
//  39.14 / 36.45, with 10 calls at 39 and 5 puts at 37 Both 83.9% / 39.18 / 36.48. Foundation only, so a swiftc harness
//  can run it beside the TS.
//

import Foundation

enum SDSale {
    /// A held sold leg that ends on or after the chosen expiry: strike, contracts, what was got a share, the years it
    /// still has after that expiry (0 when it ends then), and the IV of its own expiry.
    struct Leg: Equatable { let put: Bool; let K: Double; let n: Double; let got: Double; let t: Double; let iv: Double }
    /// A new sale at the picked strike: contracts and the premium a share.
    struct New: Equatable { let K: Double; let n: Double; let pr: Double }
    /// One side of a lane: the nearest strike, the breakeven on that side's own premium, and with both sides' premium.
    struct Side: Equatable { let K: Double; let own: Double?; let all: Double? }
    struct Seg: Equatable { let a: Double; let b: Double; let pos: Bool }
    struct Lane: Equatable {
        let cop: Double; let c: Side?; let p: Side?; let segs: [Seg]; let cr: [Double]; let prem: Double
        /// A side's breakeven: with both sides' premium when there are both, else its own (the design's be()).
        func be(put: Bool) -> Double? { (put ? p : c).flatMap { $0.all ?? $0.own } }
    }
    /// One price scale (A to B) for the three lanes.
    struct Result: Equatable { let A: Double; let B: Double; let n: Lane; let h: Lane; let b: Lane }

    /// The design's normal CDF (Abramowitz and Stegun 26.2.17), sd-engine.ts N.
    static func N(_ x: Double) -> Double {
        let t = 1 / (1 + 0.2316419 * abs(x)), d = 0.3989422804014327 * exp(-x * x / 2)
        let q = d * t * (0.31938153 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
        return x > 0 ? 1 - q : q
    }

    /// sd-engine.ts bs: Black-Scholes with rates and a dividend yield.
    static func bs(_ S: Double, _ K: Double, _ T: Double, _ r: Double, _ q: Double, _ s: Double, put: Bool) -> Double {
        let v = s * T.squareRoot(), d1 = (log(S / K) + (r - q + s * s / 2) * T) / v, d2 = d1 - v
        return put ? K * exp(-r * T) * N(-d2) - S * exp(-q * T) * N(-d1) : S * exp(-q * T) * N(d1) - K * exp(-r * T) * N(d2)
    }

    /// sd-engine.ts cdfOf: the share of moves below z, from won()'s 401 quantiles (linear between them); NaN without
    /// history.
    static func cdfOf(_ q: [Double]) -> (Double) -> Double {
        guard !q.isEmpty else { return { _ in .nan } }
        return { z in
            if z <= q[0] { return 0 }
            if z >= q[q.count - 1] { return 1 }
            var lo = 0, hi = q.count - 1
            while hi - lo > 1 { let md = (lo + hi) >> 1; if q[md] <= z { lo = md } else { hi = md } }
            let f = q[hi] > q[lo] ? (z - q[lo]) / (q[hi] - q[lo]) : 0
            return (Double(lo) + f) / Double(q.count - 1)
        }
    }

    /// sd-engine.ts sale: Held, New and Both at the chosen expiry. Only what is sold counts, from what was got for it: a
    /// new leg's P&L is its premium less intrinsic; a held leg that ends later is what was got less its Black-Scholes
    /// value then. Chance of profit sums the 5-year move distribution (scaled to today's IV) over every price where
    /// P&L > 0, ±4.5 SD in 0.02 SD steps; breakevens are every sign change on a 240-step grid, refined by bisection.
    /// `m` = IV × √(trading days ÷ 252).
    static func sale(S: Double, m: Double, r: Double, q: Double, cdf: (Double) -> Double, held: [Leg], call: New?, put: New?) -> Result {
        func val(_ x: Double, _ l: Leg) -> Double { l.t <= 1e-6 ? max(0, l.put ? l.K - x : x - l.K) : bs(x, l.K, l.t, r, q, l.iv, put: l.put) }
        let hC = held.filter { !$0.put }, hP = held.filter { $0.put }
        let hCf = { (x: Double) in hC.reduce(0) { $0 + $1.n * 100 * ($1.got - val(x, $1)) } }
        let hPf = { (x: Double) in hP.reduce(0) { $0 + $1.n * 100 * ($1.got - val(x, $1)) } }
        let nC = call.flatMap { $0.n > 0 ? $0 : nil }, nP = put.flatMap { $0.n > 0 ? $0 : nil }
        let nCf = { (x: Double) in nC.map { $0.n * 100 * ($0.pr - max(0, x - $0.K)) } ?? 0 }
        let nPf = { (x: Double) in nP.map { $0.n * 100 * ($0.pr - max(0, $0.K - x)) } ?? 0 }
        enum K3: CaseIterable { case n, h, b }
        func sd(_ k: K3) -> ((Double) -> Double, (Double) -> Double) {
            switch k {
            case .n: (nCf, nPf)
            case .h: (hCf, hPf)
            case .b: ({ nCf($0) + hCf($0) }, { nPf($0) + hPf($0) })
            }
        }
        func fn(_ k: K3) -> (Double) -> Double {
            switch k {
            case .n: { nCf($0) + nPf($0) }
            case .h: { hCf($0) + hPf($0) }
            case .b: { nCf($0) + hCf($0) + nPf($0) + hPf($0) }
            }
        }
        func chance(_ f: (Double) -> Double) -> Double {
            var s = (f(S * exp(-4.5 * m)) > 0 ? cdf(-3.99) : 0) + (f(S * exp(4.5 * m)) > 0 ? 1 - cdf(3.99) : 0)
            for i in 0..<399 {
                let z = -3.99 + Double(i) * 0.02
                if f(S * exp((z + 0.01) * m)) > 0 { s += cdf(z + 0.02) - cdf(z) }
            }
            return s
        }
        func bis(_ f: (Double) -> Double, _ a: Double, _ b: Double) -> Double? {
            if !(f(a) > 0) { return a }
            if f(b) > 0 { return nil }
            var lo = a, hi = b
            for _ in 0..<48 { let md = (lo + hi) / 2; if f(md) > 0 { lo = md } else { hi = md } }
            return (lo + hi) / 2
        }
        func ks(_ k: K3) -> ([Double], [Double]) {
            let n: ([Double], [Double]) = (nC.map { [$0.K] } ?? [], nP.map { [$0.K] } ?? [])
            let h: ([Double], [Double]) = (hC.map(\.K), hP.map(\.K))
            switch k { case .n: return n; case .h: return h; case .b: return (n.0 + h.0, n.1 + h.1) }
        }
        let hiX = S * exp(6 * m), loX = S * exp(-6 * m)
        // What is sold is one hill in price (every short call and put is concave), so its profit is one stretch: find the
        // top, then the breakeven above it (calls) and below it (puts). Not from the strike: a held leg that ends after
        // the chosen expiry still has time value there, so it can already lose at its strike (NKE Nov 13: 39.14, not 40.50).
        let LX = (0...480).map { S * exp((-6 + (12 * Double($0)) / 480) * m) }
        func top(_ f: (Double) -> Double) -> Double? {
            var bx = LX[0], by = f(bx)
            for x in LX { let y = f(x); if y > by { by = y; bx = x } }
            return by > 0 ? bx : nil
        }
        func up(_ f: (Double) -> Double) -> Double? { top(f).flatMap { bis(f, $0, hiX) } }
        func dn(_ f: (Double) -> Double) -> Double? { top(f).flatMap { bis(f, $0, loX) } }
        var sides: [K3: (c: Side?, p: Side?)] = [:]
        for k in K3.allCases {
            let (cf, pf) = sd(k), (cs, ps) = ks(k), cK = cs.min(), pK = ps.max()
            sides[k] = (c: cK.map { Side(K: $0, own: up(cf), all: pK == nil ? nil : up(fn(k))) },
                        p: pK.map { Side(K: $0, own: dn(pf), all: cK == nil ? nil : dn(fn(k))) })
        }
        // One price scale for the three lanes: ±2 SD at least, and every strike and breakeven (held to ±4 SD), 5% padding.
        let lim = { (v: Double) in max(S * exp(-4 * m), min(S * exp(4 * m), v)) }
        var pts = [S * exp(-2 * m), S * exp(2 * m)]
        for k in K3.allCases {
            for z in [sides[k]!.c, sides[k]!.p] { if let z { for v in [z.K, z.own, z.all] { if let v { pts.append(lim(v)) } } } }
        }
        var A = pts.min()!, B = pts.max()!
        let pd = (B - A) * 0.05; A -= pd; B += pd
        let G = 240, xs = (0...G).map { A + ((B - A) * Double($0)) / Double(G) }
        func lane(_ k: K3, _ prem: Double) -> Lane {
            let f = fn(k), y = xs.map(f)
            var cr: [Double] = []
            for i in 1...G where (y[i - 1] > 0) != (y[i] > 0) {
                let rt = y[i - 1] > 0 ? bis(f, xs[i - 1], xs[i]) : bis(f, xs[i], xs[i - 1])
                cr.append(rt ?? (xs[i - 1] + xs[i]) / 2)
            }
            // A crossing within 2 cents of a side's breakeven is that breakeven, so the two read the same.
            let sv = [sides[k]!.c, sides[k]!.p].compactMap { $0 }.compactMap { $0.all ?? $0.own }
            for (j, x) in cr.enumerated() { for v in sv where abs(v - x) < 0.02 { cr[j] = v } }
            let qq = [A] + cr + [B]
            let segs = (1..<qq.count).map { i in Seg(a: qq[i - 1], b: qq[i], pos: f((qq[i - 1] + qq[i]) / 2) > 0) }
            return Lane(cop: chance(f), c: sides[k]!.c, p: sides[k]!.p, segs: segs, cr: cr, prem: prem)
        }
        let premN = ((nC.map { $0.pr * $0.n } ?? 0) + (nP.map { $0.pr * $0.n } ?? 0)) * 100
        let premH = held.reduce(0) { $0 + $1.n * 100 * $1.got }
        return Result(A: A, B: B, n: lane(.n, premN), h: lane(.h, premH), b: lane(.b, premN + premH))
    }
}
