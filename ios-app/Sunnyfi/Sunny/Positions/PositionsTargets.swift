//
//  PositionsTargets.swift
//  Sunny
//
//  The Payoff target (handoff 2026-11-18 A6): a price Nik sets on the web's Payoff, per book and name, kept in
//  public.payoff_targets (members read, owners write). The phone only reads it: the Payoff shows the dashed line, the
//  ring on the curve, the "Target $38.00" pill and the P&L at it. Read once per book when Positions opens and again
//  when a name is picked, so a target set on the web shows the next time the name is opened.
//  No em dashes in any words here.
//

import Foundation
import Observation
import Supabase

@Observable
final class PositionsTargets {
    static let shared = PositionsTargets()
    /// "book|TICKER" → the target price.
    private(set) var prices: [String: Double] = [:]
    private var loading: Set<String> = []

    func price(_ book: String, _ t: String) -> Double? { prices["\(book)|\(t)"] }

    /// Reads the book's targets (a handful of rows); a failure keeps what was there.
    func load(book: String) {
        guard !loading.contains(book) else { return }
        loading.insert(book)
        Task { @MainActor in
            defer { loading.remove(book) }
            struct Row: Decodable { let ticker: String; let price: Double }
            do {
                let rows: [Row] = try await SupabaseService.client.from("payoff_targets").select("ticker,price")
                    .eq("book_id", value: book).execute().value
                var next = prices.filter { !$0.key.hasPrefix("\(book)|") }
                for r in rows where r.price > 0 { next["\(book)|\(r.ticker.uppercased())"] = r.price }
                prices = next
            } catch {
                print("[Targets] load failed: \(error)")
            }
        }
    }
}
