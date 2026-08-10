//
//  PlannerSellPages.swift
//  03 · what to sell — the page that acts.
//  04 · what is running — exists only once a sale is confirmed.
//
//  There are no selector rows. An option is not a date and a strike to be
//  assembled from two controls — it is one whole sale, so each one gets a whole
//  panel and you swipe between them. Six panels: three tiers in each of the two
//  expiries, and every panel states its own expiry rather than inheriting it
//  from a control above.
//
//  Design source: docs/design/planner_pages/.
//

import SwiftUI

private func f2(_ v: Double) -> String { String(format: "%.2f", v) }
private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
private func grouped(_ v: Double) -> String {
    let fm = NumberFormatter(); fm.numberStyle = .decimal; fm.maximumFractionDigits = 0
    return fm.string(from: NSNumber(value: v)) ?? String(Int(v))
}
private func usdK(_ v: Double) -> String {
    abs(v) >= 1000 ? "$\(Int((v / 1000).rounded()))K" : "$\(Int(v.rounded()))"
}

/// The committed sale, stored as the TRADE. Never an index into today's rail:
/// picks are recomputed every morning, so an index would silently redraw your
/// live position as whatever tomorrow's balanced tier happens to be. The two
/// indices are kept only so the pager can reopen where you left it.
struct PPCommit: Codable, Equatable {
    var chainIndex: Int?
    var engineIndex: Int?
    var tier: String
    var strike: Double
    var ct: Int
    var prem: Double
    var expiry: String
    var expCode: String?
    var soldSpot: Double
    var conviction: Int
    /// Assignment odds at the sale, 0–1 — the odds the decision was made on.
    var assign: Double?
    var onISO: String
    var onLabel: String
}

// MARK: - 03 · What to sell (paper)

struct PPSellPage: View {
    let r: PPResponse
    let spot: Double
    let commit: PPCommit?
    let onCommit: (PPCommit) -> Void

    @State private var idx: Int = 0
    @State private var ticked = false

    /// Every tier of every chain, flattened in reading order. The pager's unit is
    /// one whole sale, so this is the list it walks.
    private var opts: [(chain: PPChain, pick: PPPick, ci: Int, i: Int)] {
        (r.plan?.chains ?? []).enumerated().flatMap { ci, ch in
            (ch.picks ?? []).enumerated().map { i, p in (chain: ch, pick: p, ci: ci, i: i) }
        }
    }
    /// Open on the live position if there is one, otherwise on what conviction
    /// sized — never on the biggest credit, which is where the eye goes anyway.
    private var start: Int {
        if let c = commit,
           let k = opts.firstIndex(where: { $0.ci == (c.chainIndex ?? 0) && $0.i == (c.engineIndex ?? 0) }) {
            return k
        }
        return opts.firstIndex { $0.pick.rec == true } ?? 0
    }

    var body: some View {
        PPPage(ground: .paper) {
            HStack(alignment: .firstTextBaseline) {
                PPKicker(text: "what to sell", ground: .paper)
                Spacer()
                Text("\(Self.today()) · \(f2(spot))".uppercased())
                    .font(PP.mono(10.5)).tracking(10.5 * 0.08)
                    .foregroundStyle(PP.dim(.paper))
            }
            // What is being rolled out of. Without it the expiry choice has no anchor.
            PPFine(text: {
                let lines = (r.expiries ?? []).compactMap { $0.line }
                return lines.isEmpty ? "Nothing open. This would be a new position."
                                     : lines.joined(separator: ". ") + "."
            }(), ground: .paper, topPad: 0)
            if !opts.isEmpty {
                TabView(selection: $idx) {
                    ForEach(Array(opts.enumerated()), id: \.offset) { n, o in
                        PPOptionPanel(chain: o.chain, pick: o.pick, ci: o.ci, i: o.i, n: n,
                                      r: r, spot: spot, commit: commit,
                                      ticked: $ticked, onCommit: onCommit)
                            .tag(n)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
                // A swipe withdraws any claim made about the option just left.
                .onChange(of: idx) { _, _ in ticked = false }
                PPOptRail(count: opts.count, idx: $idx)
            }
        } base: {
            if opts.isEmpty {
                // Two very different situations, and saying "no sellable expiry" for
                // both sent me looking at the option calendar when the real cause was
                // an engine that had never heard of chains. An absent key is a stale
                // deploy; an empty array is a real answer about the market.
                PPSay(text: r.plan?.chains == nil
                      ? "This planner build needs a newer engine."
                      : "No sellable expiry.", ground: .paper)
                if r.plan?.chains == nil {
                    PPFine(text: "The response carries no chains, which means the "
                           + "deployed nvda-planner predates them. Redeploy the "
                           + "function and this page fills in.", ground: .paper)
                }
            }
        }
        .onAppear { idx = start }
    }

    private static func today() -> String {
        let fm = DateFormatter(); fm.dateFormat = "d MMM"; return fm.string(from: Date())
    }
    static func todayLabel() -> String {
        let fm = DateFormatter(); fm.dateFormat = "EEE d MMM"; return fm.string(from: Date())
    }
}

/// One whole sale. Its own expiry, its own story, its own confirm.
private struct PPOptionPanel: View {
    let chain: PPChain
    let pick: PPPick
    let ci: Int
    let i: Int
    let n: Int
    let r: PPResponse
    let spot: Double
    let commit: PPCommit?
    @Binding var ticked: Bool
    let onCommit: (PPCommit) -> Void

    private var isLive: Bool {
        guard let c = commit else { return false }
        return (c.chainIndex ?? 0) == ci && (c.engineIndex ?? 0) == i
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text((pick.rec == true
                      ? "conviction \(r.plan?.conviction ?? 0) sized this"
                      : "option \(n + 1)").uppercased())
                Spacer()
                Text(([chain.expDays.map { "\($0)d to run" }, chain.event]
                    .compactMap { $0 }.joined(separator: " · ")).uppercased())
                    .foregroundStyle(PP.dim(.paper))
            }
            .font(PP.mono(9.5)).tracking(9.5 * 0.14)
            .lineLimit(1).minimumScaleFactor(0.75)

            // The tier is the option's NAME, not a label — it reads first, as a word.
            Text((pick.tier ?? "").prefix(1).uppercased() + (pick.tier ?? "").dropFirst())
                .font(PP.disp(30, .semibold))
            if let st = pick.stance {
                Text(st).font(PP.disp(15)).lineSpacing(15 * 0.35)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Expiry, strike, quantity: the three facts that ARE the sale.
            HStack(spacing: 6) {
                pill(chain.chip ?? chain.expiry ?? "—")
                pill(f2(pick.strike ?? 0))
                pill("\(pick.ct ?? 0) lots")
            }
            Text([pick.delta.map { "\(Int($0))Δ" },
                  pick.iv.map { "iv \(f1($0))" },
                  pick.otmPct.map { "\(f1($0))% out" }]
                .compactMap { $0 }.joined(separator: " · ").uppercased())
                .font(PP.mono(10)).tracking(10 * 0.06)
                .foregroundStyle(PP.dim(.paper))
            if let note = chain.note {
                PPFine(text: note, ground: .paper, topPad: 0)
            }

            // The whole story: above the strike, between, below.
            if let ws = pick.worlds, !ws.isEmpty {
                VStack(spacing: 0) {
                    Rectangle().fill(PP.paperText.opacity(0.16)).frame(height: 1)
                    ForEach(Array(ws.enumerated()), id: \.offset) { _, w in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text((w.when ?? "").uppercased())
                                .font(PP.mono(9.5)).tracking(9.5 * 0.04)
                                .foregroundStyle(PP.dim(.paper))
                                .frame(width: 88, alignment: .leading)
                            Text(w.then ?? "").font(PP.disp(14)).lineSpacing(14 * 0.3)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 9)
                        Rectangle().fill(PP.paperText.opacity(0.10)).frame(height: 1)
                    }
                }
            }

            Spacer(minLength: 0)

            let credit = pick.income ?? ((pick.prem ?? 0) * Double(pick.ct ?? 0) * 100)
            PPNum(value: pick.label ?? usdK(credit),
                  unit: pick.creditPerDayLabel.map { "credit · \($0)" } ?? "credit",
                  size: 68, ground: .paper)
            if let be = pick.be {
                PPFine(text: "\(f2(pick.prem ?? 0)) a share, breakeven \(f2(be))"
                       + (pick.beBasisPct.map { " — \(f1($0))% over your \(f2(r.book?.buyAvg ?? 0)) basis" } ?? "")
                       + ".", ground: .paper)
            }
            if let out = pick.out {
                Text(("if called at \(f2(pick.strike ?? 0))"
                      + (r.outcome?.realisedLabel.map { " · includes \($0) realised" } ?? "")).uppercased())
                    .font(PP.mono(9.5)).tracking(9.5 * 0.08)
                    .foregroundStyle(PP.dim(.paper))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 12)
                HStack(alignment: .top, spacing: 10) {
                    trio(out.opt, "options")
                    trio(out.stockOpt, "stock + options")
                    // Null when realised P&L was not sent — an em dash, never a zero.
                    trio(out.all, "all-in")
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(PP.hairline(.paper)).frame(height: 1) }
            }

            PPConfirm(pick: pick, chain: chain, tier: pick.tier ?? "",
                      isLive: isLive, hasCommit: commit != nil,
                      onLabel: commit?.onLabel, ticked: $ticked) {
                onCommit(PPCommit(
                    chainIndex: ci, engineIndex: i,
                    tier: pick.tier ?? "", strike: pick.strike ?? 0, ct: pick.ct ?? 0,
                    prem: pick.prem ?? 0, expiry: chain.expiry ?? "", expCode: chain.expCode,
                    soldSpot: spot, conviction: r.plan?.conviction ?? 0,
                    assign: pick.assign,
                    onISO: ISO8601DateFormatter().string(from: Date()),
                    onLabel: PPSellPage.todayLabel()))
            }
        }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder private func pill(_ t: String) -> some View {
        Text(t).font(PP.mono(11))
            .padding(.horizontal, 12).frame(minHeight: 28)
            .overlay(Capsule().strokeBorder(PP.paperText.opacity(0.22), lineWidth: 1))
    }
    @ViewBuilder private func trio(_ value: String?, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value ?? "—").font(PP.mono(16)).monospacedDigit()
                .foregroundStyle(PP.paperText).lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased()).font(PP.mono(9.5)).tracking(9.5 * 0.1)
                .foregroundStyle(PP.dim(.paper))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PPConfirm: View {
    let pick: PPPick
    let chain: PPChain
    let tier: String
    let isLive: Bool
    let hasCommit: Bool
    let onLabel: String?
    @Binding var ticked: Bool
    let fire: () -> Void

    private var line: String {
        "\(pick.ct ?? 0) at \(f2(pick.strike ?? 0)), \(chain.expCode ?? chain.expiry ?? "")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLive {
                HStack(alignment: .top, spacing: 11) {
                    box(true)
                    Text("Executed \(line)." + (onLabel.map { " Logged \($0)." } ?? ""))
                        .font(PP.disp(12)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 13)
            } else {
                Button { ticked.toggle() } label: {
                    HStack(alignment: .top, spacing: 11) {
                        box(ticked)
                        Text("This is what is executed: \(line).")
                            .font(PP.disp(12)).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain).padding(.top, 13)

                Button(action: fire) {
                    HStack {
                        Text((hasCommit ? "replace the position" : "start monitoring").uppercased())
                        Spacer()
                        Text(tier.uppercased()).opacity(0.6).font(PP.mono(9.2))
                    }
                    .font(PP.mono(11.5)).tracking(11.5 * 0.06)
                    .foregroundStyle(ticked ? PP.paperMid : PP.paperText.opacity(0.45))
                    .padding(.vertical, 15).padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(ticked ? PP.paperText : PP.paperText.opacity(0.16)))
                }
                .buttonStyle(.plain).disabled(!ticked).padding(.top, 12)
            }
        }
    }

    @ViewBuilder private func box(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(on ? PP.paperText : .clear)
            .frame(width: 21, height: 21)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(PP.paperText.opacity(on ? 1 : 0.4), lineWidth: 1.5))
            .overlay(on ? Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(PP.paperMid) : nil)
    }
}

/// Dashes rather than dots: six dots stop being distinguishable, and a dash reads
/// as "one of a series" where a dot reads as "a page".
private struct PPOptRail: View {
    let count: Int
    @Binding var idx: Int
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { n in
                Capsule()
                    .fill(n == idx ? PP.paperText : PP.paperText.opacity(0.20))
                    .frame(width: 24, height: 3)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { idx = n } }
            }
            Spacer()
            Text("\(idx + 1) / \(count)").font(PP.mono(9.5)).tracking(9.5 * 0.12)
                .foregroundStyle(PP.dim(.paper))
        }
        .padding(.top, 14)
    }
}

// MARK: - 04 · The position you are running (ink)

/// Reads the COMMITTED trade, never today's rail.
struct PPMonitorPage: View {
    let r: PPResponse
    let spot: Double
    let commit: PPCommit
    let onStandDown: () -> Void

    var body: some View {
        let room = commit.strike - commit.soldSpot
        let used = min(max((spot - commit.soldSpot) / (room == 0 ? 1 : room), 0), 1)
        let left = commit.strike > 0 ? (commit.strike - spot) / spot * 100 : 0
        let moved = spot - commit.soldSpot
        let credit = commit.prem * Double(commit.ct) * 100
        let uncapped = max(0, (r.book?.shares ?? 0) - Double(commit.ct) * 100)

        PPPage(ground: .ink) {
            HStack(alignment: .firstTextBaseline) {
                PPKicker(text: "the position you are running", ground: .ink)
                Spacer()
                Text("sold \(commit.onLabel)".uppercased())
                    .font(PP.mono(10.5)).tracking(10.5 * 0.08)
                    .foregroundStyle(PP.dim(.ink))
            }
            Text("\(commit.ct) \(r.ticker ?? "NVDA") \(commit.expiry) \(f2(commit.strike)) C at \(f2(commit.prem))")
                .font(PP.mono(13))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("sold at \(f2(commit.soldSpot))".uppercased()); Spacer()
                    Text("cap \(f2(commit.strike))".uppercased())
                }
                .font(PP.mono(9.5)).tracking(9.5 * 0.1).foregroundStyle(PP.dim(.ink))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(PP.inkText.opacity(0.14))
                        Capsule().fill(PP.inkText).frame(width: max(3, geo.size.width * used))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text("now \(f2(spot)) · \(moved == 0 ? "unchanged" : (moved > 0 ? "+" : "−") + f2(abs(moved)))".uppercased())
                    Spacer()
                    Text("\(grouped(uncapped)) uncapped".uppercased())
                }
                .font(PP.mono(9.5)).tracking(9.5 * 0.1).foregroundStyle(PP.dim(.ink))
            }
            PPFine(text: "The credit is yours either way. What is still open is the "
                   + "\(f2(left))% of upside between here and the cap, on "
                   + "\(grouped(Double(commit.ct) * 100)) of your \(grouped(r.book?.shares ?? 0)) shares.",
                   ground: .ink, topPad: 0)
        } base: {
            PPNum(value: "\(f2(left))%", unit: "of room left", ground: .ink)
            PPSay(text: [commit.assign.map { "\(Int(($0 * 100).rounded()))% odds it gets called." },
                         (r.plan?.chains?.first?.expDays).map { "\($0) sessions to run." }]
                .compactMap { $0 }.joined(separator: " "), ground: .ink)
            HStack(alignment: .top, spacing: 10) {
                trio(usdK(credit), "collected")
                trio(usdK((commit.strike - commit.soldSpot) * Double(commit.ct) * 100 + credit),
                     "if called at \(Int(commit.strike))")
                trio("\(Int((r.plan?.chains?.first?.keepPct ?? 0).rounded()))%", "delta kept")
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(PP.hairline(.ink)).frame(height: 1) }
            .padding(.top, 20)

            HStack {
                Text("\(commit.tier) · conviction \(commit.conviction) at the sale".uppercased())
                    .foregroundStyle(PP.inkText)
                Spacer()
                Button(action: onStandDown) {
                    Text("stand down".uppercased()).underline().foregroundStyle(PP.dim(.ink))
                }
                .buttonStyle(.plain)
            }
            .font(PP.mono(11)).tracking(11 * 0.1)
            .padding(.vertical, 15).padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(PP.inkText.opacity(0.22), lineWidth: 1))
            .padding(.top, 14)
        }
    }

    @ViewBuilder private func trio(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(PP.mono(17)).foregroundStyle(PP.inkText).monospacedDigit()
            Text(label.uppercased()).font(PP.mono(10)).tracking(10 * 0.1)
                .foregroundStyle(PP.dim(.ink)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
