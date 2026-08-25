//
//  SunnyWeek.swift
//  Sunny — the Monday card. Backed by the `income-week` function.
//
//  Two sections and nothing else: what Benzinga moved on the held names last
//  week, and what last week earned in premium.
//
//  ⚠ NO POSITION DETAIL. Nik: "Dont include position detials just Benzinga
//  detials and what we have earned last week." No shares, no coverage, no
//  floor, no strikes. The per-position Awareness Cards carry all of that, and
//  repeating it is what made the old Income card say the same thing every day.
//
//  ⚠ MONDAY ONLY, AND GONE ONCE READ. The engine decides both: it knows the day
//  and it keeps one row per week in income_week_seen. The card never asks
//  "is it Monday" itself — a client that reasons about dates and a server that
//  reasons about dates will disagree the first time one of them is in a
//  different timezone.
//
//  The paper treatment is shared with the Awareness Card through PaperSheet,
//  PaperHeading and PaperBullet rather than copied, so the two cannot drift.
//

import SwiftUI

// MARK: - store

@Observable
final class WeekStore {
    var card: SunnyWeekModel?
    var error: String?
    private var loading = false

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/income-week") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 45
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        // A real open CONSUMES the week: the engine marks it read so it does not
        // come back tomorrow. -peekWeek is for looking without spending it.
        let peek = ProcessInfo.processInfo.arguments.contains("-peekWeek")
        r.httpBody = Data((peek ? "{\"peek\":true}" : "{}").utf8)
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { error = "HTTP \(h.statusCode)"; return }
            let p = try JSONDecoder().decode(WeekPayload.self, from: d)
            guard p.show == true else { card = nil; return }
            card = SunnyWeekModel(p)
        } catch { self.error = String(describing: error) }
    }
}

private struct WeekPayload: Decodable {
    struct Week: Decodable { var from: String; var to: String; var label: String }
    struct Ev: Decodable { var when: String; var text: String }
    struct Earn: Decodable { var ticker: String; var amount: String; var net: Double }
    var week: Week?
    var show: Bool?
    var changed: [Ev]?
    var earned: [Earn]?
    var earned_total: String?
    var quiet: String?
}

struct SunnyWeekModel {
    let label: String
    let total: String
    let changed: [(when: String, text: String)]
    let earned: [(ticker: String, amount: String)]
    let quiet: String?

    fileprivate init(_ p: WeekPayload) {
        label = p.week?.label ?? ""
        total = p.earned_total ?? ""
        changed = (p.changed ?? []).map { (when: $0.when, text: $0.text) }
        earned = (p.earned ?? []).map { (ticker: $0.ticker, amount: $0.amount) }
        quiet = p.quiet
    }
}

// MARK: - the card

struct SunnyWeekCard: View {
    let m: SunnyWeekModel
    /// SHELL.md §9: this card is read-once. It has no ticker, so it has nowhere
    /// to file — reading it removes it from the feed until it is due again.
    var onRead: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            section("What changed") {
                // A quiet week says so BEFORE the headlines, so a list of wire
                // pieces cannot imply that something happened.
                if let q = m.quiet {
                    PaperBullet { body(q) }
                }
                ForEach(Array(m.changed.enumerated()), id: \.offset) { _, e in
                    PaperBullet { dated(e.when, e.text) }
                }
            }
            section("What it earned", isLast: onRead == nil) {
                ForEach(Array(m.earned.enumerated()), id: \.offset) { _, e in
                    PaperBullet { body("\(e.ticker)  \(e.amount)") }
                }
            }
            if let onRead {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PaperReadControl(action: onRead)
                }
                .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
            }
        }
        .paperSheet()
    }

    /// Same three-line stack as the Awareness Card: meta line, then a baseline
    /// row of a handwritten subject and an Inter figure. Here the subject is the
    /// week rather than a ticker, and the figure is what it earned.
    private var header: some View {
        VStack(alignment: .leading, spacing: S.gap1) {
            Text(m.label)
                .font(S.handAlt(S.tHandMeta))
                .tracking(S.track(S.tHandMeta, 0.02))
                .foregroundStyle(S.paperInkMeta)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("Last week")
                    .font(S.hand(S.tHandTitle))
                    .foregroundStyle(S.paperInkTicker)
                Text(m.total)
                    .font(S.inter(S.tPaperSpot, S.wSemiN))
                    .tracking(S.track(S.tPaperSpot, -0.03))
                    .foregroundStyle(S.paperInkStrong)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 14, trailing: 20))
    }

    @ViewBuilder
    private func section<C: View>(_ heading: String, isLast: Bool = false,
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            PaperHeading(text: heading)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Top padding is 0 on every section; the heading's rule separates them.
        .padding(EdgeInsets(top: 0, leading: 20, bottom: isLast ? 20 : 16, trailing: 20))
    }

    private func body(_ t: String) -> some View {
        Text(t)
            .font(S.inter(S.tPaperBody, S.wBodyN))
            .lineSpacing(S.leading(S.tPaperBody, S.wBodyN, S.lhPaperBody))
            .foregroundStyle(S.paperInk)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The date leads, in meta ink, then the sentence. One Text so it wraps as
    /// one paragraph — a date in its own column would strand short lines.
    /// ⚠ Inter, not Kalam: DIGEST-CARD §2 gives Kalam the timestamp and NOTHING
    /// else, and this is a date inside a body line.
    private func dated(_ when: String, _ text: String) -> some View {
        var a = AttributedString("\(when)   ")
        a.font = S.inter(S.tPaperBody, S.wBodyN)
        a.foregroundColor = S.paperInkMeta
        var b = AttributedString(text)
        b.font = S.inter(S.tPaperBody, S.wBodyN)
        b.foregroundColor = S.paperInk
        return Text(a + b)
            .lineSpacing(S.leading(S.tPaperBody, S.wBodyN, S.lhPaperBody))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
