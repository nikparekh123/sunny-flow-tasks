//
//  SunnyOptionsData.swift
//  Sunny — the options cards' one contract.
//
//  Build sheet: OPTIONS-CARDS.md. One payload feeds both surfaces, because the
//  weekly-yield card's last bar must equal the yield-progress card's "this
//  week" figure and two endpoints would let them drift.
//

import SwiftUI

@Observable
final class OptionsStore {
    private(set) var data: OptionsPayload?
    private(set) var error: String?
    private(set) var loading = false
    private var loadedAt: Date?

    /// Version bumps on every load so a screen model can key its cache off it.
    private(set) var version = 0

    func load(force: Bool = false) async {
        if loading { return }
        if !force, let at = loadedAt, Date().timeIntervalSince(at) < 300 { return }
        loading = true; defer { loading = false }
        do {
            var r = URLRequest(url: URL(string: Secrets.supabaseURL
                + "/functions/v1/options-cards")!)
            r.httpMethod = "POST"
            r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
            r.setValue("Bearer " + Secrets.supabasePublishableKey,
                       forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = Data("{}".utf8)
            let (d, _) = try await URLSession.shared.data(for: r)
            data = try JSONDecoder().decode(OptionsPayload.self, from: d)
            error = nil; loadedAt = Date(); version &+= 1
        } catch { self.error = String(describing: error) }
    }
}

struct OptionsPayload: Decodable {
    let ok: Bool
    let date: String
    let book: OptionsBook
    let positions: [OptionsPosition]
}

struct OptionsBook: Decodable {
    let paid: Int, collected: Int, windowCredit: Int
    let weekly: [BookWeek]
    let avgPct: Double
    let thisWeek: Int, bestWeek: Int
    /// ⚠ NOT A FORECAST. The eight-week average × 52. The one-word label the
    /// sheet mandates cannot carry that caveat, so it lives here.
    let yearly: Double
    let legs: Int
    /// `bars` ≤5 · `paged` 6–10 · `rows` 11+. The leg count picks it and
    /// nothing else does.
    let form: String
    let rolling: Int, nextExpiry: Int, kept: Int

    struct BookWeek: Decodable, Identifiable {
        let week: String, credit: Int, pct: Double
        var id: String { week }
    }
}

struct OptionsPosition: Decodable, Identifiable {
    let t: String, co: String
    let leap: String
    let paid: Int, mark: Int
    /// ⚠ A CHANGE IN MARK, NOT CASH THAT MOVED. A LEAP held all week moves no
    /// cash and still gains or loses every week.
    let markWeek: Int
    /// Every credit ever on the name, Nik's ruling. It predates the LEAP, which
    /// is why `windowCredit` exists beside it: the eight bars total THAT.
    let collected: Int
    let windowCredit: Int
    let week: Int
    let weekly: [Int]
    let weeksRun: Int, weeksLeft: Int
    let longN: Int, shortN: Int
    let dLong: Double, dShort: Double
    /// Share equivalents, signed, with the two leg counts weighted separately —
    /// the book runs 15 long against 14 short on NFLX on purpose.
    let netDelta: Int
    let shorts: [ShortLeg]
    var id: String { t }

    struct ShortLeg: Decodable, Identifiable {
        let n: Int, k: Double, exp: String
        let credit: Int, value: Int
        /// THE ACTION. `verdictOf` reads this and nothing else.
        let itm: Bool
        /// THE MONEY, of the credit received. Disagrees with `itm` often, and
        /// that disagreement is the point.
        let captured: Int
        let delta: Double
        let contract: String
        var id: String { "\(n)|\(k)|\(exp)" }
    }
}
