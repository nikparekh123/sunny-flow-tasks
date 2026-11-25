//
//  PositionsTries.swift
//  Sunny
//
//  Try in Payoff (handoff 2026-11-24 §4, §6): a strike tried from Intelligence is kept per book and name in
//  public.payoff_tries (book_id, ticker, id, side 's'|'b', ty 'c'|'p', strike, expiry, n, on_, set_at; members read,
//  owners write: as payoff_targets), in place of the prototype's localStorage sunny.try186. It shows in Every leg as a
//  leg "from Intelligence" with a switch and ✕, and counts in Payoff and the Greeks.
//  A tried leg is priced on the phone with the chain's IV at its own strike and expiry (sunny-sd exps[].ivK), never the
//  name's single IV: entry = its Black-Scholes value now, so its P&L starts at 0 today.
//  A write that fails (a viewer of the book, no network) keeps the change on the phone for the session.
//  No em dashes in any words here.
//

import Foundation
import Observation
import Supabase

/// One tried strike, as the table keeps it.
struct PosTry: Identifiable, Hashable {
    let id: String
    /// "s" sold, "b" bought.
    let side: String
    /// "c" call, "p" put.
    let ty: String
    let K: Double
    /// The expiry, ISO ("2026-11-27").
    let ex: String
    let n: Int
    var on: Bool
    /// "2026-11-27:c:160:2": what Intelligence's Your trade compares with.
    var sig: String { "\(ex):\(ty):\(PE.jsNum(K)):\(n)" }
}

/// A tried strike priced for Payoff and the Greeks.
struct PosTryLeg: Hashable {
    let t: PosTry
    /// The chain's IV at the strike and expiry.
    let iv: Double
    /// Calendar days to the expiry from the grid's pricing time (the same clock the grid's stops count on).
    let T: Double
    /// Its value a share now (entry and mark).
    let en: Double
    /// Contracts, sold negative.
    var q: Double { t.side == "s" ? -Double(t.n) : Double(t.n) }
    var put: Bool { t.ty == "p" }

    func value(_ x: Double, _ tt: Double) -> Double { PE.bs(put: put, S: x, K: t.K, T: max(0, T - tt) / 365, iv: iv).p }
    /// P&L from now at a price and a stop's date.
    func pl(_ x: Double, _ tt: Double) -> Double { q * 100 * (value(x, tt) - en) }
    /// Delta in shares, gamma (shares a $1), theta ($ a day), vega ($ a vol point) at a price and date.
    func greeks(_ x: Double, _ tt: Double) -> (d: Double, g: Double, th: Double, vg: Double) {
        let b = PE.bs(put: put, S: x, K: t.K, T: max(0, T - tt) / 365, iv: iv), m = q * 100
        return (m * b.d, m * b.g, m * b.t, m * b.vg)
    }

    /// The chain's IV at a strike, read on the straight line between the two nearest strikes (held at the ends).
    static func ivAt(_ e: SDReply.Exp, _ K: Double) -> Double {
        let pts = (e.ivK ?? []).compactMap { p -> (Double, Double)? in p.count >= 2 && p[0] > 0 && p[1] > 0 ? (p[0], p[1]) : nil }.sorted { $0.0 < $1.0 }
        guard let f = pts.first, let l = pts.last else { return e.iv }
        if K <= f.0 { return f.1 }
        if K >= l.0 { return l.1 }
        for i in 1..<pts.count where pts[i].0 >= K {
            let a = pts[i - 1], b = pts[i], w = b.0 > a.0 ? (K - a.0) / (b.0 - a.0) : 0
            return a.1 + (b.1 - a.1) * w
        }
        return e.iv
    }

    /// Prices the name's tries on its reply: the IV at the strike for that expiry, the days on the grid's clock (a
    /// grid leg on the same expiry, else the reply's calendar days). An expiry no longer in the reply is left out.
    static func price(_ tries: [PosTry], reply: SDReply?, model m: PositionsModel?) -> [PosTryLeg] {
        guard let r = reply, let m, m.S0 > 0 else { return [] }
        return tries.compactMap { x in
            guard let e = r.exps.first(where: { $0.ex == x.ex }) else { return nil }
            let iv = ivAt(e, x.K)
            let T = m.legs.first { $0.iso == x.ex }?.T ?? e.cd
            let en = PE.bs(put: x.ty == "p", S: m.S0, K: x.K, T: T / 365, iv: iv).p
            return PosTryLeg(t: x, iv: iv, T: T, en: en)
        }
    }
}

@MainActor @Observable
final class PositionsTries {
    static let shared = PositionsTries()
    /// "book|TICKER" → the tries, in the order they were made.
    private(set) var rows: [String: [PosTry]] = [:]
    /// Bumped on every change: the Positions memo knows a new set.
    private(set) var version = 0
    @ObservationIgnored private var loading: Set<String> = []

    func list(_ book: String, _ t: String) -> [PosTry] { rows["\(book)|\(t)"] ?? [] }

    private struct Row: Codable {
        let book_id: String; let ticker: String; let id: String; let side: String; let ty: String
        let strike: Double; let expiry: String; let n: Int; let on_: Bool
    }

    private var offline: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("-skipAuth")
        #else
        return false
        #endif
    }

    /// Reads the book's tries (a handful of rows) when Positions opens; a failure keeps what was there.
    func load(book: String) {
        guard !offline, !loading.contains(book) else { return }
        loading.insert(book)
        Task {
            defer { loading.remove(book) }
            do {
                let got: [Row] = try await SupabaseService.client.from("payoff_tries")
                    .select("book_id,ticker,id,side,ty,strike,expiry,n,on_").eq("book_id", value: book).order("set_at").execute().value
                var next = rows.filter { !$0.key.hasPrefix("\(book)|") }
                for r in got {
                    next["\(book)|\(r.ticker.uppercased())", default: []]
                        .append(PosTry(id: r.id, side: r.side, ty: r.ty, K: r.strike, ex: String(r.expiry.prefix(10)), n: r.n, on: r.on_))
                }
                rows = next; version += 1
            } catch {
                print("[Tries] load failed: \(error)")
            }
        }
    }

    /// Try in Payoff: the name's tries become this trade (sold); an empty list is Undo.
    func set(book: String, t: String, _ list: [(ty: String, K: Double, ex: String, n: Int)]) {
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let L = list.filter { $0.n > 0 }.enumerated().map { i, x in PosTry(id: "i\(stamp)\(i)", side: "s", ty: x.ty, K: x.K, ex: x.ex, n: x.n, on: true) }
        rows["\(book)|\(t)"] = L.isEmpty ? nil : L
        version += 1
        guard !offline else { return }
        Task {
            do {
                try await SupabaseService.client.from("payoff_tries").delete().eq("book_id", value: book).eq("ticker", value: t).execute()
                if !L.isEmpty {
                    try await SupabaseService.client.from("payoff_tries")
                        .insert(L.map { Row(book_id: book, ticker: t, id: $0.id, side: $0.side, ty: $0.ty, strike: $0.K, expiry: $0.ex, n: $0.n, on_: $0.on) })
                        .execute()
                }
            } catch {
                print("[Tries] save failed: \(error)")
            }
        }
    }

    /// A tried leg's own switch in Every leg.
    func setOn(book: String, t: String, ids: Set<String>, _ on: Bool) {
        let k = "\(book)|\(t)"
        guard var L = rows[k] else { return }
        for i in L.indices where ids.contains(L[i].id) { L[i].on = on }
        rows[k] = L; version += 1
        guard !offline else { return }
        Task {
            do {
                try await SupabaseService.client.from("payoff_tries").update(["on_": on])
                    .eq("book_id", value: book).eq("ticker", value: t).in("id", values: Array(ids)).execute()
            } catch {
                print("[Tries] switch failed: \(error)")
            }
        }
    }

    /// ✕ on a tried leg in Every leg.
    func remove(book: String, t: String, id: String) {
        let k = "\(book)|\(t)"
        rows[k] = rows[k]?.filter { $0.id != id }
        if rows[k]?.isEmpty == true { rows[k] = nil }
        version += 1
        guard !offline else { return }
        Task {
            do {
                try await SupabaseService.client.from("payoff_tries").delete()
                    .eq("book_id", value: book).eq("ticker", value: t).eq("id", value: id).execute()
            } catch {
                print("[Tries] remove failed: \(error)")
            }
        }
    }
}
