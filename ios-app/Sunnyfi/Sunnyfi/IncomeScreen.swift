//
//  IncomeScreen.swift
//  Sunnyfi — Ink · the income sleeve
//
//  Several names, ONE rule: own a block, sell an ATM call and an ATM put every
//  week, hold a long-dated OTM put as a floor. Spec: docs/INCOME_SLEEVE_SPEC.md
//
//  Reads the income-sleeve edge function. The function does every calculation;
//  this file only lays out what it returns.
//
//  ── Why this screen stacks instead of using InkRail ──────────────────────────
//  Every other Ink page is a horizontal rail of fixed 348pt cards. This one is a
//  vertical list, on purpose: the names are RANKED, and a rail puts the third
//  name off-screen where the ordering stops meaning anything. The rank is the
//  point, so all of it has to be visible at once.
//
//  ── Tone ─────────────────────────────────────────────────────────────────────
//  There is no warning state here. An earlier build had CAREFUL, which fired on
//  a missing floor and printed "CAREFUL — no floor set" against a sleeve that had
//  not opened yet. Nik's word for it was fear-mongering, and he was right: a
//  state that never blocks anything is a tone of voice, not information. Facts
//  only. A missing floor reads "none yet".
//

import SwiftUI

// MARK: - the payload

struct IncomeSleeve: Decodable {
    var ok: Bool?
    var asof: String?
    var expiry: String?
    var note: String?
    var portfolio: Portfolio?
    var names: [Name]?
    var error: String?

    struct Portfolio: Decodable {
        var invested: Double?
        var collected: Double?
        /// How far the blended average sits BELOW what the shares cost, in percent.
        var average_below_pct: Double?
        var floor_cost: Double?
        var floor_pct_of_premium: Double?
        var floor_weeks_to_pay: Int?
        var premium_this_week: Double?
        var expiring_friday: Int?
    }

    struct Write: Decodable {
        var calls: Int?; var call_strike: Double?; var call_mid: Double?
        var puts: Int?;  var put_strike: Double?;  var put_mid: Double?
        var credit: Double?
    }

    struct Name: Decodable, Identifiable {
        var ticker: String
        var id: String { ticker }
        var rank: Int?
        var state: String?
        var verdict: String?
        var why: [String]?
        var spot: Double?
        var rank_line: String?
        var where_line: String?
        var trend_line: String?
        var floor_line: String?
        var avg_line: String?
        var avg_split_line: String?
        var put_commitment: Double?
        /// "600 shares · $207,000 · 32% of the sleeve". Replaced the old
        /// "0 of 600 shares": Nik removed targets, so there is no progress to
        /// report, only how the money actually sits across the names.
        var balance_line: String?
        var share_of_sleeve: Double?
        var new_low: Bool?
        var write: Write?
    }
}

// MARK: - store

@Observable
final class IncomeStore {
    var sleeve: IncomeSleeve?
    var error: String?
    var loading = false
    var loadedAt: Date?

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        error = nil
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/income-sleeve") else {
            error = "bad url"; return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data("{}".utf8)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                error = "HTTP \(http.statusCode)"; return
            }
            let parsed = try JSONDecoder().decode(IncomeSleeve.self, from: data)
            if let e = parsed.error { error = e; return }
            sleeve = parsed
            loadedAt = Date()
        } catch {
            self.error = String(describing: error)
        }
    }
}

// MARK: - formatting

private func inUsd(_ v: Double) -> String {
    let n = abs(v)
    if n >= 1_000_000 { return "$\(String(format: "%.2f", v / 1_000_000))m" }
    if n >= 10_000 { return "$\(Int(v / 1000).formatted())k" }
    return "$" + Int(v.rounded()).formatted(.number.grouping(.automatic))
}

private func inStrike(_ v: Double?) -> String {
    guard let v else { return "—" }
    return v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
}

/// "2026-08-21" -> "Fri 21 Aug". The expiry is the one date on this screen that
/// has to read at a glance, so it gets a weekday.
private func inDay(_ iso: String?) -> String {
    guard let iso, iso.count >= 10 else { return "—" }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "America/New_York")
    guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
    let o = DateFormatter(); o.dateFormat = "EEE d MMM"; o.timeZone = f.timeZone
    return o.string(from: d)
}

// MARK: - the screen

struct IncomeScreen: View {
    @State private var store = IncomeStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                InkSectionHead(title: "Income",
                               count: store.sleeve?.asof.map { inDay($0).uppercased() },
                               icon: "arrow.clockwise",
                               onAction: { Task { await store.load() } })

                if let s = store.sleeve, let p = s.portfolio {
                    HeaderBlock(p: p, expiry: s.expiry)
                    ForEach(ranked(s.names ?? [])) { n in
                        NameRow(n: n, expiry: s.expiry)
                    }
                    if let note = s.note { NoteFoot(text: note) }
                } else if let e = store.error {
                    Quiet(title: "Could not load", body: e)
                } else {
                    Quiet(title: "Loading", body: "Reading the sleeve.")
                }
                Color.clear.frame(height: 104)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { if store.sleeve == nil { await store.load() } }
    }

    /// Rank order, with anything unranked (a no-price row) pushed to the bottom
    /// rather than dropped: a name that failed to price is still a name he holds.
    private func ranked(_ ns: [IncomeSleeve.Name]) -> [IncomeSleeve.Name] {
        ns.sorted { ($0.rank ?? 99) < ($1.rank ?? 99) }
    }
}

// MARK: - header

/// What went in, what came back, what the shares really cost now, and whether the
/// protection has paid for itself.
///
/// This used to lead with stock / put commitment / NET AT RISK. Nik removed the
/// net figure on 2026-08-16: the put commitment is on every row, so the doubling
/// is still visible name by name, and a seven-figure headline on a screen he
/// opens daily was noise rather than information.
private struct HeaderBlock: View {
    let p: IncomeSleeve.Portfolio
    let expiry: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Figure(k: "Invested", v: inUsd(p.invested ?? 0))
                Figure(k: "Collected", v: inUsd(p.collected ?? 0), hue: (p.collected ?? 0) > 0 ? Ink.gain : Ink.text, rule: true)
            }
            Rectangle().fill(Ink.hair).frame(height: 1).padding(.vertical, 16)
            Line(k: "Average",
                 v: p.average_below_pct.map { "\(String(format: "%.1f", $0))% below cost" } ?? "nothing yet")
            Line(k: "Floors", v: floorText)
            Line(k: "This week",
                 v: "\(inUsd(p.premium_this_week ?? 0)) to collect, writes to \(inDay(expiry))")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var floorText: String {
        guard let fc = p.floor_cost, fc > 0 else { return "none yet, nothing to pay back" }
        var s = inUsd(fc)
        if let pct = p.floor_pct_of_premium { s += ", \(pct)% of premium" }
        if let w = p.floor_weeks_to_pay { s += ", paid back in \(w) week\(w == 1 ? "" : "s")" }
        return s
    }

    private struct Figure: View {
        let k: String; let v: String; var hue: Color = Ink.text; var rule: Bool = false
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(k.uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.07).foregroundStyle(Ink.dim)
                InkRoll(text: v, font: InkFont.mono(28, .medium), tracking: 28 * -0.03, color: hue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, rule ? 14 : 0)
            .overlay(alignment: .leading) { if rule { Rectangle().fill(Ink.hair).frame(width: 1) } }
        }
    }

    private struct Line: View {
        let k: String; let v: String
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(k.uppercased()).font(InkFont.mono(10.5)).tracking(10.5 * 0.07)
                    .foregroundStyle(Ink.dim).frame(width: 86, alignment: .leading)
                Text(v).font(InkFont.mono(12.5)).tracking(12.5 * -0.01)
                    .foregroundStyle(Ink.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - one name

private struct NameRow: View {
    let n: IncomeSleeve.Name
    let expiry: String?

    private var skipped: Bool { (n.state ?? "") == "SKIP" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // rank · ticker · spot ......................... verdict
            HStack(alignment: .center, spacing: 10) {
                RankPip(n: n.rank)
                Text(n.ticker).font(InkFont.serif(22)).tracking(22 * -0.01).foregroundStyle(Ink.text)
                if let s = n.spot {
                    Text(String(format: "%.2f", s)).font(InkFont.mono(14)).tracking(14 * -0.02)
                        .foregroundStyle(Ink.dim)
                }
                Spacer(minLength: 8)
                Text((n.verdict ?? "").uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.12)
                    .foregroundStyle(verdictHue).multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 14)

            Field(k: "Earned", v: n.rank_line ?? "nothing yet")
            if skipped {
                // Plain text, NOT Ink.loss. Rendering the skip reason in the loss
                // colour put the alarm straight back in through the palette: on the
                // opening week all three names read "no shares yet" in warning
                // orange, which is the exact tone CAREFUL was deleted for. A skip
                // is a fact about the week, not a loss.
                Field(k: "Skip", v: (n.why ?? []).first ?? "blocked")
            } else if let w = n.write {
                Field(k: "Write", v: writeLine(w))
                Field(k: "Money", v: "puts commit \(inUsd(n.put_commitment ?? 0))")
            }
            if let b = n.balance_line {
                Field(k: "Block", v: b)
            }
            Field(k: "Avg", v: avgLine)
            Field(k: "Where", v: [n.where_line, n.trend_line].compactMap { $0 }.joined(separator: " · "),
                  hue: (n.new_low ?? false) ? Ink.loss : Ink.text)
            Field(k: "Floor", v: n.floor_line ?? "none yet")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.surface))
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .opacity(skipped ? 0.62 : 1)
    }

    /// "4 puts 345 · 2 calls 345 · Fri 21 Aug · $5,010". Puts lead: on a sleeve
    /// that is still filling its blocks the put is the trade being put on and the
    /// call is whatever the held shares can cover, which is often nothing.
    private func writeLine(_ w: IncomeSleeve.Write) -> String {
        var parts: [String] = []
        if (w.puts ?? 0) > 0 { parts.append("\(w.puts!) puts \(inStrike(w.put_strike))") }
        if (w.calls ?? 0) > 0 { parts.append("\(w.calls!) calls \(inStrike(w.call_strike))") }
        if parts.isEmpty { parts.append("nothing to write") }
        parts.append(inDay(expiry))
        parts.append(inUsd(w.credit ?? 0))
        return parts.joined(separator: " · ")
    }

    /// The average, then what each LEG took off it. Confirmed with Nik 2026-08-16:
    /// this is the split of the credit, NOT the average that would result if the
    /// calls carried the shares away.
    private var avgLine: String {
        guard let a = n.avg_line else { return "nothing yet" }
        guard let s = n.avg_split_line else { return a }
        return "\(a) · \(s)"
    }

    private var verdictHue: Color {
        switch n.verdict ?? "" {
        case "good week to sell": return Ink.gain
        case "poor week to sell": return Ink.loss
        default: return Ink.dim
        }
    }

    private struct RankPip: View {
        let n: Int?
        var body: some View {
            Text(n.map(String.init) ?? "—").font(InkFont.mono(11, .medium)).tracking(11 * 0.02)
                .foregroundStyle(n == 1 ? Ink.invertText : Ink.text)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(n == 1 ? Ink.invertBg : .clear))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(n == 1 ? .clear : Ink.hair, lineWidth: 1))
        }
    }

    /// A labelled line. An EMPTY value renders nothing at all rather than an empty
    /// row: a deploy that is behind the app leaves some of these nil, and a blank
    /// gap where a fact should be reads as missing data instead of as absent data.
    private struct Field: View {
        let k: String; let v: String; var hue: Color = Ink.text
        var body: some View {
            if v.trimmingCharacters(in: .whitespaces).isEmpty { EmptyView() } else { row }
        }
        private var row: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(k.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.14)
                    .foregroundStyle(Ink.dim).frame(width: 52, alignment: .leading)
                Text(v).font(InkFont.mono(12)).tracking(12 * -0.01).foregroundStyle(hue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 5)
        }
    }
}

// MARK: - footer

/// A note, not a total. The blocks here are the tool, not the holding, and a
/// screen that ends on a big premium figure quietly says the opposite.
private struct NoteFoot: View {
    let text: String
    var body: some View {
        Text(text)
            .font(InkFont.display(13, .regular))
            .foregroundStyle(Ink.dim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 18)
    }
}

private struct Quiet: View {
    let title: String; let body_: String
    init(title: String, body: String) { self.title = title; self.body_ = body }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(InkFont.serif(24)).foregroundStyle(Ink.text)
            Text(body_).font(InkFont.display(14)).foregroundStyle(Ink.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 60)
    }
}
