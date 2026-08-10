//
//  PlannerSellPages.swift
//  04 · what to sell — the page that acts.
//  05 · what is running — exists only once a sale is confirmed.
//
//  These two are one story told twice: the rail is the choice, the chart is the
//  room it leaves, and page 05 is the same trade read back against today's spot.
//
//  Design source: docs/design/planner_pages/.
//

import SwiftUI

private let TIERS = ["conservative", "balanced", "aggressive"]

private func f2(_ v: Double) -> String { String(format: "%.2f", v) }
private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
private func grouped(_ v: Double) -> String {
    let fm = NumberFormatter(); fm.numberStyle = .decimal; fm.maximumFractionDigits = 0
    return fm.string(from: NSNumber(value: v)) ?? String(Int(v))
}
/// Credits read in whole thousands on the cards — the design's own compaction.
private func usdK(_ v: Double) -> String {
    let a = abs(v)
    if a >= 1000 { return "$\(Int((v / 1000).rounded()))K" }
    return "$\(Int(v.rounded()))"
}

/// What the committed sale is, stored as the TRADE and not as an index into
/// today's rail. picks are recomputed every morning, so picks[1] tomorrow is a
/// different strike, count and premium — an index would silently redraw the
/// live position as whatever tomorrow's balanced tier happens to be.
struct PPCommit: Codable, Equatable {
    /// Position in the ENGINE's picks array, not in the sorted rail. The rail is
    /// ordered furthest-strike-first for reading; planner_commits is keyed on the
    /// engine's own order, and confusing the two records the wrong tier against
    /// the outcome — which would poison the record rather than just misdraw it.
    /// Optional so a commit stored before this field existed still decodes.
    var engineIndex: Int?
    var tier: String
    var strike: Double
    var ct: Int
    var prem: Double
    var expiry: String
    var soldSpot: Double
    var conviction: Int
    /// Assignment probability AT THE SALE, 0–1. Carried rather than re-read from
    /// today's rail: the odds that belong on the monitoring page are the ones the
    /// decision was made on, and tomorrow's rail may not even contain this strike.
    var assign: Double?
    var onISO: String
    var onLabel: String
}

// MARK: - 04 · What to sell (paper)

struct PPSellPage: View {
    let r: PPResponse
    let spot: Double
    let commit: PPCommit?
    let onCommit: (PPCommit) -> Void

    @State private var sel: Int = 0
    @State private var ticked = false

    /// Furthest strike first: at high conviction the top of the rail is the
    /// consistent end of it. A tier inside the put floor sorts last, priced but
    /// unpickable.
    private var ladder: [(pick: PPPick, tier: String, engineIndex: Int)] {
        let picks = r.plan?.picks ?? []
        let tagged = picks.enumerated().map { i, p in
            (pick: p, tier: TIERS.indices.contains(i) ? TIERS[i] : "tier \(i + 1)", engineIndex: i)
        }
        return tagged.sorted {
            ($0.pick.blocked == nil ? 0 : 1, -($0.pick.strike ?? 0))
                < ($1.pick.blocked == nil ? 0 : 1, -($1.pick.strike ?? 0))
        }
    }
    private var chosen: (pick: PPPick, tier: String, engineIndex: Int)? {
        ladder.indices.contains(sel) ? ladder[sel] : ladder.first
    }

    var body: some View {
        PPPage(ground: .paper) {
            HStack(alignment: .firstTextBaseline) {
                PPKicker(text: "what to sell", ground: .paper)
                Spacer()
                Text("\(Self.todayShort()) → \(r.plan?.expiry ?? "—") · \(r.plan?.expDays ?? 0)d".uppercased())
                    .font(PP.mono(10.5)).tracking(10.5 * 0.08)
                    .foregroundStyle(PP.dim(.paper))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(Array(ladder.enumerated()), id: \.offset) { i, row in
                        PPStrikeCard(pick: row.pick, tier: row.tier,
                                     spot: spot, on: i == sel)
                        .onTapGesture {
                            guard row.pick.blocked == nil else { return }
                            sel = i; ticked = false      // changing tier clears the tick
                        }
                    }
                }
                .padding(.horizontal, PP.pagePadX)
            }
            .padding(.horizontal, -PP.pagePadX)
            // What is already open. This came off the deleted decision page, and it
            // belongs here: the week you roll INTO is not a sensible choice without
            // the week you are rolling OUT of.
            PPFine(text: {
                let lines = (r.expiries ?? []).compactMap { $0.line }
                return lines.isEmpty ? "Nothing open. This would be a new position."
                                     : lines.joined(separator: ". ") + "."
            }(), ground: .paper, topPad: 0)
            if let c = chosen?.pick {
                PPPayoff(pick: c, shares: r.book?.shares ?? 0, spot: spot,
                         em: r.plan?.expectedMove ?? max(1, spot * 0.02))
            }
        } base: {
            if let row = chosen {
                let p = row.pick
                let credit = p.income ?? ((p.prem ?? 0) * Double(p.ct ?? 0) * 100)
                PPNum(value: usdK(credit), unit: "credit at \(f2(p.strike ?? 0))",
                      size: 84, ground: .paper)
                PPFine(text: "\(row.tier.prefix(1).uppercased() + row.tier.dropFirst()), "
                       + "\(f2(p.prem ?? 0)) a share on \(p.ct ?? 0) contracts."
                       + (p.wasCt.map { " At a neutral 50 this tier was \($0)." } ?? "")
                       + (r.plan?.hedgeNote.map { " \($0)." } ?? ""), ground: .paper)
                if let be = p.be {
                    PPFine(text: "Breakeven \(f2(be)): the \(f2(p.strike ?? 0)) strike plus the "
                           + "\(f2(p.prem ?? 0)) you were paid"
                           + (p.beBasisPct.map { ", \(f1($0))% above your \(f2(r.book?.buyAvg ?? 0)) basis" } ?? "")
                           + ".", ground: .paper)
                }
                PPConfirm(pick: p, tier: row.tier, expiry: r.plan?.expiry ?? "",
                          commit: commit, ticked: $ticked) {
                    onCommit(PPCommit(
                        engineIndex: row.engineIndex,
                        tier: row.tier, strike: p.strike ?? 0, ct: p.ct ?? 0,
                        prem: p.prem ?? 0, expiry: r.plan?.expiry ?? "",
                        soldSpot: spot, conviction: r.plan?.conviction ?? 0,
                        assign: p.assign,
                        onISO: ISO8601DateFormatter().string(from: Date()),
                        onLabel: Self.today()))
                }
            }
        }
        .onAppear {
            // The rail is SORTED furthest-strike-first for reading, so its first
            // entry is the conservative end — not the recommendation. Opening
            // there quietly proposed a different trade than the one conviction
            // sized: the engine's picks[0] is the target strike, and that is what
            // the page must land on. Falls back to the first sellable tier only
            // if the target is blocked by the floor.
            if let i = ladder.firstIndex(where: { $0.engineIndex == 0 && $0.pick.blocked == nil })
                ?? ladder.firstIndex(where: { $0.pick.blocked == nil }) { sel = i }
        }
    }

    private static func today() -> String {
        let fm = DateFormatter(); fm.dateFormat = "EEE d MMM"; return fm.string(from: Date())
    }
    /// The meta row reads as a span — from today, to the expiry, over N sessions.
    private static func todayShort() -> String {
        let fm = DateFormatter(); fm.dateFormat = "d MMM"; return fm.string(from: Date())
    }
}

/// Selected is INVERSION, never a hue. A tier inside the floor is dashed at 50%
/// with its strike struck through and the refusal in place of its size.
private struct PPStrikeCard: View {
    let pick: PPPick
    let tier: String
    let spot: Double
    let on: Bool

    private var otm: Double {
        guard spot > 0, let k = pick.strike else { return 0 }
        return (k / spot - 1) * 100
    }
    private var blocked: Bool { pick.blocked != nil }
    private var fg: Color { on ? Color(red: 0.969, green: 0.969, blue: 0.957) : PP.paperText }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tier.uppercased()).font(PP.mono(9)).tracking(9 * 0.16).opacity(0.58)
            Text(f2(pick.strike ?? 0)).font(PP.mono(24))
                .strikethrough(blocked, color: fg)
            Text(blocked ? (pick.blocked ?? "")
                 : "\(pick.ct ?? 0) contracts · \(f2(otm))% out")
                .font(PP.mono(9.5)).tracking(9.5 * 0.06).opacity(0.62)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(fg.opacity(0.22)).frame(height: 1).padding(.top, 2)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                greek("iv", pick.iv.map { f1($0) })
                greek("Δ", pick.delta.map { String(Int(($0 * (abs($0) <= 1 ? 100 : 1)).rounded())) })
                greek("Γ", pick.gamma.map { String(format: "%.3f", $0) })
            }
            Text(usdK(pick.income ?? ((pick.prem ?? 0) * Double(pick.ct ?? 0) * 100)))
                .font(PP.mono(19)).strikethrough(blocked, color: fg)
        }
        .padding(EdgeInsets(top: 13, leading: 15, bottom: 15, trailing: 15))
        .frame(width: 152, alignment: .leading)
        .foregroundStyle(fg)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(on ? PP.paperText : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18).strokeBorder(
                PP.paperText.opacity(on ? 1 : (blocked ? 0.20 : 0.16)),
                style: StrokeStyle(lineWidth: 1, dash: blocked ? [4, 4] : []))
        )
        .opacity(blocked ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.18), value: on)
    }

    @ViewBuilder private func greek(_ label: String, _ value: String?) -> some View {
        GridRow {
            Text(label.uppercased()).font(PP.mono(9.5)).tracking(9.5 * 0.12).opacity(0.62)
            Text(value ?? "—").font(PP.mono(12.5)).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// The whole position from today — shares plus the call — not the option leg
/// alone. It rises with the stock until the strike, then flattens to the
/// uncovered shares; that kink IS the cap. Geometry only, no new figures.
private struct PPPayoff: View {
    let pick: PPPick
    let shares: Double
    let spot: Double
    let em: Double

    private var k: Double { pick.strike ?? spot }
    private var credit: Double { pick.income ?? ((pick.prem ?? 0) * Double(pick.ct ?? 0) * 100) }
    private var covered: Double { Double(pick.ct ?? 0) * 100 }
    private var lo: Double { spot - em }
    private var hi: Double { spot + em }
    /// The position's own breakeven: where the credit stops covering the shares'
    /// loss. Not the option's breakeven, which is the strike plus the premium.
    private var be: Double { shares > 0 ? spot - credit / shares : spot }

    private func pos(_ v: Double) -> Double {
        shares * (v - spot) + credit - max(0, v - k) * covered
    }
    private var bounds: (top: Double, bot: Double) {
        let vals = [pos(lo), pos(k), pos(hi)]
        return ((vals.max() ?? 1) * 1.15, (vals.min() ?? -1) * 1.15)
    }
    private func X(_ v: Double, _ W: Double) -> Double { (v - lo) / max(hi - lo, 0.0001) * W }
    private func Y(_ v: Double, _ H: Double) -> Double {
        let b = bounds
        return H - (v - b.bot) / max(b.top - b.bot, 0.0001) * H
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(grouped(shares)) shares + call".uppercased())
                    .foregroundStyle(PP.dim(.paper))
                Spacer()
                Text("\(grouped(max(0, shares - covered))) uncapped".uppercased())
                    .foregroundStyle(PP.paperText)
            }
            .font(PP.mono(9.5)).tracking(9.5 * 0.1)

            GeometryReader { geo in
                ZStack {
                    // The loss region — with the discs, the only colour in the app.
                    Path { p in
                        p.move(to: .init(x: X(lo, geo.size.width), y: Y(0, geo.size.height)))
                        p.addLine(to: .init(x: X(lo, geo.size.width), y: Y(pos(lo), geo.size.height)))
                        p.addLine(to: .init(x: X(be, geo.size.width), y: Y(0, geo.size.height)))
                        p.closeSubpath()
                    }.fill(PP.lossHue.opacity(0.20))

                    Path { p in
                        p.move(to: .init(x: 0, y: Y(0, geo.size.height)))
                        p.addLine(to: .init(x: geo.size.width, y: Y(0, geo.size.height)))
                    }.stroke(PP.paperText, lineWidth: 1)

                    Path { p in
                        p.move(to: .init(x: X(spot, geo.size.width), y: 16))
                        p.addLine(to: .init(x: X(spot, geo.size.width), y: geo.size.height))
                    }.stroke(PP.paperText.opacity(0.28), lineWidth: 1)

                    // Shares plus the call: rises with the stock to the strike, then
                    // flattens to the uncovered shares. That kink IS the cap.
                    Path { p in
                        p.move(to: .init(x: X(lo, geo.size.width), y: Y(pos(lo), geo.size.height)))
                        p.addLine(to: .init(x: X(k, geo.size.width), y: Y(pos(k), geo.size.height)))
                        p.addLine(to: .init(x: X(hi, geo.size.width), y: Y(pos(hi), geo.size.height)))
                    }.stroke(PP.paperText, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))

                    Circle().fill(PP.paperText).frame(width: 7, height: 7)
                        .position(x: X(k, geo.size.width), y: Y(pos(k), geo.size.height))
                    Circle().fill(PP.paperMid)
                        .overlay(Circle().strokeBorder(PP.paperText, lineWidth: 2))
                        .frame(width: 7, height: 7)
                        .position(x: X(be, geo.size.width), y: Y(0, geo.size.height))

                    Text("now \(f2(spot))".uppercased())
                        .font(PP.mono(9)).tracking(9 * 0.1)
                        .foregroundStyle(PP.paperText.opacity(0.72))
                        .position(x: min(max(28, X(spot, geo.size.width)), geo.size.width - 30), y: 6)
                    Text("capped \(f2(k))".uppercased())
                        .font(PP.mono(9)).tracking(9 * 0.1)
                        .foregroundStyle(PP.paperText.opacity(0.72))
                        .position(x: min(X(k, geo.size.width) + 42, geo.size.width - 34),
                                  y: Y(pos(k), geo.size.height) + 17)
                }
            }
            .frame(height: 150)
            .padding(.top, 18)
        }
        .padding(.top, 16)
    }
}

private struct PPConfirm: View {
    let pick: PPPick
    let tier: String
    let expiry: String
    let commit: PPCommit?
    @Binding var ticked: Bool
    let fire: () -> Void

    private var isLive: Bool {
        guard let c = commit else { return false }
        return c.strike == pick.strike && c.ct == pick.ct && c.expiry == expiry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLive, let c = commit {
                HStack(alignment: .top, spacing: 11) {
                    box(checked: true)
                    Text("Executed \(c.ct) at \(f2(c.strike)), \(expiry). Logged \(c.onLabel).")
                        .font(PP.disp(12.5)).foregroundStyle(PP.paperText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 18)
            } else {
                Button { ticked.toggle() } label: {
                    HStack(alignment: .top, spacing: 11) {
                        box(checked: ticked)
                        Text("This is what is executed: \(pick.ct ?? 0) at \(f2(pick.strike ?? 0)), \(expiry).")
                            .font(PP.disp(12.5)).foregroundStyle(PP.paperText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 18)

                Button(action: fire) {
                    HStack {
                        Text((commit == nil ? "start monitoring" : "replace the position").uppercased())
                        Spacer()
                        Text(tier.uppercased()).opacity(0.6).font(PP.mono(9.6))
                    }
                    .font(PP.mono(12)).tracking(12 * 0.06)
                    .foregroundStyle(ticked ? Color(red: 0.969, green: 0.969, blue: 0.957)
                                            : PP.paperText.opacity(0.45))
                    .padding(.vertical, 15).padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(ticked ? PP.paperText : PP.paperText.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .disabled(!ticked)
                .padding(.top, 16)
            }
        }
    }

    @ViewBuilder private func box(checked: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(checked ? PP.paperText : .clear)
            .frame(width: 21, height: 21)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(PP.paperText.opacity(checked ? 1 : 0.4), lineWidth: 1.5))
            .overlay(checked
                     ? Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(PP.paperMid) : nil)
    }
}

// MARK: - 05 · The position you are running (ink)

/// Reads the COMMITTED trade, never today's rail. The room bar is the only
/// arithmetic: how far spot has travelled from the sale toward the cap.
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
                        Capsule().fill(PP.inkText)
                            .frame(width: max(3, geo.size.width * used))
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
                         "\(r.plan?.expDays ?? 0) sessions to run."]
                .compactMap { $0 }.joined(separator: " "), ground: .ink)
            HStack(alignment: .top, spacing: 10) {
                trio(usdK(credit), "collected")
                trio(usdK((commit.strike - commit.soldSpot) * Double(commit.ct) * 100 + credit),
                     "if called at \(Int(commit.strike))")
                trio("\(Int((r.plan?.keepPct ?? 0).rounded()))%", "delta kept")
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(PP.hairline(.ink)).frame(height: 1) }
            .padding(.top, 20)

            HStack {
                Text("\(commit.tier) · conviction \(commit.conviction) at the sale".uppercased())
                    .foregroundStyle(PP.inkText)
                Spacer()
                Button(action: onStandDown) {
                    Text("stand down".uppercased()).underline()
                        .foregroundStyle(PP.dim(.ink))
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
                .foregroundStyle(PP.dim(.ink))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
