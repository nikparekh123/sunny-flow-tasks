//
//  SunnyBook.swift
//  The Book (final cards, 23 Sep 2026): Performance and Allocation as one
//  ranked ledger behind two tabs. rank · name · the answer · its reference;
//  five rows, then `Show all N` in place.
//
//  ⚠ ADDED BESIDE PERFORMANCE AND ALLOCATION, NOT IN PLACE OF THEM. Nik,
//  23 Sep: "let me just first see it, how it looks, and then we remove it."
//
//  ⚠ ONE DERIVATION, TWO CARDS. Performance rows are `SunnyProgramme.pgRows`
//  and Allocation rows are the server's `allocationCard.book`, the same two
//  sources the old cards read, so neither tab can disagree with its card.
//
//  ⚠ THE FOOTER SAYS OPEN, NOT OWED (Nik, 17 Sep): the credit on legs still
//  open, the word Performance already prints. Money reads through `optMoney`
//  on Performance (K and M, Nik 14 Sep) and `usdM` on Allocation, as before.
//

import SwiftUI

struct SunnyBook: View {
    let programme: ProgrammeBlock?
    let legs: [LongLeg]
    let allocation: AllocationCard?

    @AppStorage("sunnyfi.book.tab") private var tabRaw = "perf"
    /// The ledger expanded past five. Shared across tabs, survives a pull.
    @State private var more = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let limit = 5
    private var perf: Bool { tabRaw != "alloc" }

    private struct Row: Identifiable {
        let t: String, mid: String, fig1: String, ink1: Color, fig2: String
        var id: String { t }
    }
    private struct Read {
        var scope = "", meta = "", eyebrow = "", hero = "", heroSub = "", heroNote = ""
        var heroInk: Color = S.ink
        var colName = "", col1 = "", col2 = ""
        var rows: [Row] = []
        var stats: [(String, String, Color)] = []
    }

    private func sinceLabel(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        let mon = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m) else { return iso }
        return "since \(d) \(mon[m - 1])"
    }

    private var read: Read {
        var r = Read()
        if perf {
            guard let block = programme else { return r }
            let rs = SunnyProgramme.pgRows(block, legs)
            let kept = rs.reduce(0) { $0 + $1.kept }, open = rs.reduce(0) { $0 + $1.open }
            let mark = rs.reduce(0) { $0 + $1.mark }, inv = rs.reduce(0) { $0 + $1.inv }
            let net = kept + mark
            let pct = inv > 0 ? Double(net) / Double(inv) * 100 : 0
            r.scope = "performance"; r.meta = sinceLabel(block.since); r.eyebrow = "NET"
            r.hero = signedMoney(Double(net)); r.heroInk = net < 0 ? S.lossText : S.gainText
            r.heroSub = (pct < 0 ? "down " : "up ") + String(format: "%.1f%%", abs(pct))
            r.heroNote = "on \(optMoney(inv)) invested \u{00B7} ranked by net on invested"
            r.colName = "NAME"; r.col1 = "NET %"; r.col2 = "NET $"
            /* Every name with cash invested, best return first. */
            r.rows = rs.filter { $0.inv > 0 }.sorted { $0.pct > $1.pct }.map {
                Row(t: $0.t, mid: "", fig1: bkPct1($0.pct), ink1: $0.pct < 0 ? S.lossText : S.gainText,
                    fig2: signedMoney(Double($0.net)))
            }
            r.stats = [("BANKED", optMoney(kept), S.ink),
                       ("OPEN", optMoney(open), S.ink),
                       ("AT MARK", signedMoney(Double(mark)), mark < 0 ? S.lossText : S.gainText)]
        } else {
            guard let al = allocation else { return r }
            /* ⚠ SORTED BY INVESTED, ALWAYS; the note names the sort. */
            let rs = al.book.sorted { $0.inv > $1.inv }
            let inv = rs.reduce(0) { $0 + $1.inv }, now = rs.reduce(0) { $0 + $1.now }
            r.scope = "allocation"; r.meta = "\(rs.count) name\(rs.count == 1 ? "" : "s")"
            r.eyebrow = "VALUE NOW"
            /* A value is not a direction: the hero stays ink. */
            r.hero = usdM(now); r.heroInk = S.ink
            r.heroSub = "on \(usdM(inv)) invested"
            r.heroNote = (inv > 0 ? alPct((now / inv - 1) * 100) : "0%") + " on the cash \u{00B7} ranked by invested"
            r.colName = "NAME \u{00B7} SHARE"; r.col1 = "NOW"; r.col2 = "INVESTED"
            r.rows = rs.map { x in
                let share = inv > 0 ? x.inv / inv * 100 : 0
                return Row(t: x.t, mid: share < 0.5 ? "<1%" : "\(Int(share.rounded()))%",
                           fig1: usdM(x.now), ink1: x.now >= x.inv ? S.gainText : S.lossText,
                           fig2: usdM(x.inv))
            }
            r.stats = [("INVESTED", usdM(inv), S.ink),
                       ("NOW", usdM(now), now >= inv ? S.gainText : S.lossText),
                       ("NAMES", "\(rs.count)", S.ink)]
        }
        return r
    }

    var body: some View {
        let r = read
        let shown = more ? r.rows : Array(r.rows.prefix(Self.limit))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                    Text("Book").font(S.inter(S.t14, S.wBoldN))
                        .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                    Text(r.scope).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
                }
                .fixedSize()
                Spacer(minLength: 0)
                Text(r.meta).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute).lineLimit(1)
            }
            Spacer().frame(height: 18)
            tabRow
            Spacer().frame(height: 20)
            label(r.eyebrow)
            Spacer().frame(height: 11)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(r.hero).font(S.inter(S.t22, S.wBoldN)).tracking(S.track(S.t22, -0.03))
                    .foregroundStyle(r.heroInk).sunnyLineBox(S.t22)
                Text(r.heroSub).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            .lineLimit(1)
            Spacer().frame(height: 8)
            Text(r.heroNote).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                .lineLimit(1).minimumScaleFactor(0.85).sunnyLineBox(S.t12)
            Spacer().frame(height: 22)

            /* THE LEDGER: rank · name (+ share) · the answer · its reference. */
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                label("#").frame(width: 18, alignment: .leading)
                label(r.colName).frame(maxWidth: .infinity, alignment: .leading)
                label(r.col1)
                label(r.col2).frame(minWidth: 60, alignment: .trailing)
            }
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }

            ForEach(Array(shown.enumerated()), id: \.element.id) { i, row in
                HStack(alignment: .center, spacing: 12) {
                    Text("\(i + 1)").font(S.inter(S.t12, S.wSemiN)).foregroundStyle(S.mute)
                        .frame(width: 18, alignment: .leading)
                    HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                        Text(row.t).font(S.inter(S.t15, S.wSemiN)).tracking(S.track(S.t15, -0.015))
                            .foregroundStyle(S.ink)
                        if !row.mid.isEmpty {
                            Text(row.mid).font(S.inter(S.t12, S.wSemiN)).foregroundStyle(S.ink2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.fig1).font(S.inter(S.t13, S.wBoldN)).tracking(S.track(S.t13, -0.02))
                        .foregroundStyle(row.ink1)
                    Text(row.fig2).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                        .frame(minWidth: 60, alignment: .trailing)
                }
                .lineLimit(1)
                .frame(height: 15)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }
                .opacity(appeared || reduceMotion ? 1 : 0)
                .animation(reduceMotion ? nil : S.easeSettle(0.4).delay(Double(i) * 0.04), value: appeared)
            }
            .id(tabRaw)

            /* SHOW ALL, the one underline. Absent at five or fewer. */
            if r.rows.count > Self.limit {
                Text(more ? "Show top \(Self.limit)" : "Show all \(r.rows.count)")
                    .font(S.inter(S.t12, S.wSemiN)).foregroundStyle(S.mute)
                    .sunnyHint()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { more.toggle() }
            }

            Spacer().frame(height: 22)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 18)
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(r.stats.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 7) {
                        label(s.0)
                        Text(s.1).font(S.inter(S.t15, S.wBoldN)).tracking(S.track(S.t15, -0.02))
                            .foregroundStyle(s.2).lineLimit(1).sunnyLineBox(S.t15)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: S.content - 48, alignment: .leading)
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24))
        .frame(width: S.content, alignment: .top)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        .measure("book")
        .task(id: "\(tabRaw)|\(more)") {
            appeared = false
            try? await Task.sleep(for: .milliseconds(20))
            appeared = true
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
            .foregroundStyle(S.mute).lineLimit(1).sunnyLineBox(S.t10)
    }

    /// Two words, left, 18 apart, on one strong rule.
    private var tabRow: some View {
        HStack(alignment: .bottom, spacing: 18) {
            ForEach([("perf", "Performance"), ("alloc", "Allocation")], id: \.0) { k, word in
                let on = (k == "perf") == perf
                VStack(spacing: 0) {
                    Text(word).font(S.inter(S.t12, on ? S.wBoldN : S.wMidN))
                        .foregroundStyle(on ? S.ink : S.mute).lineLimit(1).sunnyLineBox(S.t12)
                    Spacer().frame(height: 10)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(on ? S.ink : .clear).frame(height: 2)
                }
                .contentShape(Rectangle())
                .onTapGesture { tabRaw = k }
            }
            Spacer(minLength: 0)
        }
        .background(alignment: .bottom) { Rectangle().fill(S.ruleColorStrong).frame(height: 1) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: tabRaw)
    }
}

/// `+98.2%` · `−4.0%`.
private func bkPct1(_ v: Double) -> String {
    (v < 0 ? "\u{2212}" : "+") + String(format: "%.1f", abs(v)) + "%"
}
