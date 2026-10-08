//
//  SunnyBook.swift
//  The Book (final cards, 23 Sep 2026): Performance and Allocation as one
//  ranked ledger behind two tabs. rank · name · the answer · its reference;
//  five rows, then `Show all N` in place.
//
//  ⚠ ADDED BESIDE PERFORMANCE AND ALLOCATION, NOT IN PLACE OF THEM. Nik,
//  23 Sep: "let me just first see it, how it looks, and then we remove it."
//
//  ⚠ ONE DERIVATION, TWO CARDS. Performance rows are `pgRows`
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
    /// Long legs closed since the book began, per name (28 Sep 2026).
    var closed: ClosedCard? = nil
    /// For a name's detail sheet: its open short legs, expiries, spot.
    var positions: [OptionsPosition] = []
    var intrinsic: IntrinsicBlock? = nil
    var prices: [PriceRow] = []

    @AppStorage("sunnyfi.book.tab") private var tabRaw = "perf"
    /// The ledger expanded past five. Shared across tabs, survives a pull.
    @State private var more = false
    /// The name whose detail sheet is open.
    @State private var sheetT: String? = nil
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
            let rs = perfRows(block)
            let kept = rs.reduce(0) { $0 + $1.kept }, open = rs.reduce(0) { $0 + $1.open }
            let mark = rs.reduce(0) { $0 + $1.atMark }, inv = rs.reduce(0) { $0 + $1.inv }
            let done = rs.reduce(0) { $0 + $1.closed }
            let net = kept + done + mark
            let pct = inv > 0 ? Double(net) / Double(inv) * 100 : 0
            r.scope = "performance"; r.meta = sinceLabel(block.since); r.eyebrow = "NET"
            r.hero = signedMoney(Double(net)); r.heroInk = net < 0 ? S.lossText : S.gainText
            r.heroSub = (pct < 0 ? "down " : "up ") + String(format: "%.1f%%", abs(pct))
            r.heroNote = "on \(optMoney(inv)) invested \u{00B7} ranked by net on invested"
            r.colName = "NAME"; r.col1 = "NET %"; r.col2 = "NET $"
            /* Every name with cash invested, best return first. */
            r.rows = rs.filter { $0.inv > 0 }.sorted { $0.pct > $1.pct }.map {
                Row(t: $0.t, mid: $0.closed == 0 ? "" : "closed " + signedMoney(Double($0.closed)),
                    fig1: bkPct1($0.pct), ink1: $0.pct < 0 ? S.lossText : S.gainText,
                    fig2: signedMoney(Double($0.net)))
            }
            /* ⚠ CLOSED IS ITS OWN STAT (Nik, 28 Sep 2026). What selling long legs
               back realized, IBKR's figure where it has one; AT MARK is now the
               legs still held alone. Banked + Closed + At mark = Net. */
            r.stats = [("BANKED", optMoney(kept), S.ink),
                       ("OPEN", optMoney(open), S.ink),
                       ("CLOSED", signedMoney(Double(done)), done < 0 ? S.lossText : S.gainText),
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
                            /* The ticker opens its detail: bought, sold, closed. */
                            .sunnyHint()
                        if !row.mid.isEmpty {
                            Text(row.mid).font(S.inter(S.t12, perf ? S.wMidSmN : S.wSemiN))
                                .foregroundStyle(perf ? S.mute : S.ink2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    /* 15/500, every list's right-hand figure (Nik, 27 Sep 2026). */
                    Text(row.fig1).font(S.inter(S.t15, S.wMidN)).tracking(S.track(S.t15, -0.02))
                        .foregroundStyle(row.ink1)
                    Text(row.fig2).font(S.inter(S.t15, S.wMidN)).tracking(S.track(S.t15, -0.02))
                        .foregroundStyle(S.mute)
                        .frame(minWidth: 60, alignment: .trailing)
                }
                .lineLimit(1)
                .frame(height: 15)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { openSheet(row.t) }
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
            /* ⚠ THE DECK'S FOOTER, NOT THE SHEET'S SMALLER ONE (Nik, 28 Sep
               2026: the Book's 15pt stats looked unlike every other card's).
               Label 10/700 over 19/700, 5 between, columns inset as OptFooter. */
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(r.stats.enumerated()), id: \.offset) { i, s in
                    if i > 0 { Spacer(minLength: 12) }
                    VStack(alignment: .leading, spacing: 5) {
                        label(s.0)
                        Text(s.1).font(S.inter(S.t19, S.wBoldN)).tracking(S.track(S.t19, -0.025))
                            .foregroundStyle(s.2).lineLimit(1)
                    }
                    .fixedSize()
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
        .fullScreenCover(isPresented: sheetOpen) {
            sheetHost.presentationBackground(.clear)
        }
        .task(id: "\(tabRaw)|\(more)") {
            appeared = false
            try? await Task.sleep(for: .milliseconds(20))
            appeared = true
        }
    }

    // MARK: performance rows

    /// One row a name: kept and open from the ledger, the legs still held at
    /// mark against average cost, and what closing long legs realized. The
    /// closed ledger replaces the legs' `rz`, which only covered legs still
    /// partly held and so dropped every fully closed hedge from the net.
    private struct PerfRow {
        let t: String, kept: Int, open: Int, atMark: Int, closed: Int, inv: Int
        var net: Int { kept + closed + atMark }
        var pct: Double { inv > 0 ? Double(net) / Double(inv) * 100 : 0 }
    }
    private func perfRows(_ block: ProgrammeBlock) -> [PerfRow] {
        let names = Set(block.rows.map(\.t)).union(legs.map(\.t))
            .union(closed?.names.keys.map { $0 } ?? [])
        return names.map { t in
            let src = block.rows.first { $0.t == t }
            let mine = legs.filter { $0.t == t }
            let mark = mine.reduce(0.0) { $0 + ($1.m - $1.cost) * Double($1.n) }
            let done = closed.map { $0.names[t]?.total ?? 0 }
                ?? Int(mine.reduce(0.0) { $0 + ($1.rz ?? 0) }.rounded())
            return PerfRow(t: t, kept: src?.kept ?? 0, open: src?.open ?? 0,
                           atMark: Int(mark.rounded()), closed: done,
                           inv: Int(mine.reduce(0.0) { $0 + $1.cost * Double($1.n) }.rounded()))
        }
    }

    // MARK: the detail sheet

    private func openSheet(_ t: String) {
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr) { sheetT = t }
    }
    private var sheetOpen: Binding<Bool> {
        Binding(get: { sheetT != nil }, set: { if !$0 {
            var tr = Transaction(); tr.disablesAnimations = true
            withTransaction(tr) { sheetT = nil }
        } })
    }
    @ViewBuilder private var sheetHost: some View {
        if let t = sheetT {
            let row = programme?.rows.first { $0.t == t }
            GlassSheetHost(content: { close in
                SunnyNameSheet(t: t, spot: prices.first { $0.ticker == t }?.spot,
                               legs: legs.filter { $0.t == t },
                               shorts: positions.first { $0.t == t }?.shorts ?? [],
                               closed: closed?.names[t],
                               intrinsic: intrinsic?.rows.first { $0.t == t },
                               banked: row?.kept ?? 0, openCredit: row?.open ?? 0,
                               onClose: close)
            }, onDismissed: {
                var tr = Transaction(); tr.disablesAnimations = true
                withTransaction(tr) { sheetT = nil }
            })
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
