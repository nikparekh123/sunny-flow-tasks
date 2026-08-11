//
//  PlannerMechanismPage.swift
//  What to sell — as a mechanism, not a menu.
//
//  The planner's whole answer is two numbers: how much exposure to keep, and how
//  far out to sell it. Which expiry, which strike, how many contracts all fall
//  out of those two once a week is chosen — and that arithmetic is faster to do
//  than six pre-computed versions of it are to read.
//
//  This replaces the six swiped panels. What it removes on purpose: the expiry
//  selection, the three tier names, the ladder. A distance also cannot produce a
//  strike below spot, which is how the in-the-money "conservative" call that the
//  ladder kept offering stops being possible rather than being guarded against.
//

import SwiftUI

private func f2(_ v: Double) -> String { String(format: "%.2f", v) }
private func f1(_ v: Double) -> String { String(format: "%.1f", v) }
private func grouped(_ v: Double) -> String {
    let fm = NumberFormatter(); fm.numberStyle = .decimal; fm.maximumFractionDigits = 0
    return fm.string(from: NSNumber(value: v)) ?? String(Int(v))
}

struct PPMechanismPage: View {
    let r: PPResponse
    let spot: Double
    let commit: PPCommit?
    let onCommit: (PPCommit) -> Void
    @State private var ticked = false

    /// Delta or shares. The same decision counted two ways — delta is what the
    /// model sizes on, shares is what actually gets called away — so this is a
    /// lens, not a setting, and it does not persist.
    @State private var unit: Unit = .delta
    enum Unit: String, CaseIterable { case delta = "delta", shares = "shares" }

    private var m: PPMechanism? { r.plan?.mechanism }

    var body: some View {
        PPPage(ground: .paper) {
            HStack(alignment: .firstTextBaseline) {
                PPKicker(text: "what to sell", ground: .paper)
                    .foregroundStyle(PP.paperText)
                Spacer()
                Text("\(Self.today()) · \(f2(spot))".uppercased())
                    .font(PP.mono(10.5)).tracking(10.5 * 0.08)
                    .foregroundStyle(PP.paperText)
            }
            // The position being rolled out of, so the answer has something to
            // be an answer about.
            PPFine(text: {
                let lines = (r.expiries ?? []).compactMap { $0.line }
                return lines.isEmpty ? "Nothing open. This would be a new position."
                                     : lines.joined(separator: ". ") + "."
            }(), ground: .paper, topPad: 0)

            if let m {
                Picker("", selection: $unit) {
                    ForEach(Unit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)

                PPKeepBlock(m: m, unit: unit)
            }
        } base: {
            if let m {
                // The distance is the page's number. Keep is the other half and sits
                // above it — one hero, per the layout law, and this is the one that
                // decides where the cap lands.
                PPNum(value: m.otmPct.map { "\(f1($0))%" } ?? "—",
                      unit: "out of the money", size: 88, ground: .paper)
                PPSay(text: sigmaLine(m), ground: .paper)
                Text([m.strike.map { "That is \(f2($0)) on the \(m.expiry.map(Self.day) ?? "next") expiry" },
                      m.contracts.map { "\($0) contracts" }]
                    .compactMap { $0 }.joined(separator: ", ") + ".")
                    .font(PP.disp(15)).lineSpacing(15 * 0.4)
                    .foregroundStyle(PP.paperText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
                if let t = m.keepPctTarget, let a = m.keepPct, abs(t - a) >= 2 {
                    // The floor binding is the one thing that makes the achieved
                    // answer differ from the asked-for one. Saying so is the whole
                    // reason both numbers are carried.
                    Text("Conviction asked for \(Int(t))%. The hedge floor takes it to \(Int(a))%.")
                        .font(PP.disp(15)).lineSpacing(15 * 0.4)
                        .foregroundStyle(PP.paperText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 9)
                }
                PPMechConfirm(m: m, commit: commit, ticked: $ticked) {
                    onCommit(PPCommit(
                        chainIndex: 0, engineIndex: 0,
                        tier: "mechanism",
                        strike: m.strike ?? 0, ct: m.contracts ?? 0,
                        prem: 0, expiry: m.expiry ?? "",
                        expCode: m.expiry.map { String($0.suffix(5)) },
                        soldSpot: spot, conviction: r.plan?.conviction ?? 0,
                        assign: nil,
                        onISO: ISO8601DateFormatter().string(from: Date()),
                        onLabel: PPMechanismPage.todayLabel()))
                }
            } else {
                PPSay(text: r.plan?.mechanism == nil && r.plan?.chains == nil
                      ? "This planner build needs a newer engine."
                      : "No sellable expiry.", ground: .paper)
            }
        }
    }

    /// A distance is silent about the thing that matters. Under one sigma the
    /// strike sits inside the move the market is already pricing, which reads as
    /// safely out and is not.
    private func sigmaLine(_ m: PPMechanism) -> String {
        guard let s = m.sigmas else { return "Keep the rest." }
        let em = m.expectedMove.map { " One sigma is \(f2($0))." } ?? ""
        if s < 1 { return "That is \(f2(s)) sigma, inside the move being priced.\(em)" }
        if s < 1.5 { return "That is \(f2(s)) sigma, just past the expected move.\(em)" }
        return "That is \(f2(s)) sigma, clear of the expected move.\(em)"
    }

    private static func today() -> String {
        let fm = DateFormatter(); fm.dateFormat = "d MMM"; return fm.string(from: Date())
    }
    static func todayLabel() -> String {
        let fm = DateFormatter(); fm.dateFormat = "EEE d MMM"; return fm.string(from: Date())
    }
    static func day(_ iso: String) -> String {
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "d MMM"; return out.string(from: d)
    }
}

/// Keep, in whichever unit is being read. Both are the same decision — the toggle
/// changes the words, never the trade.
private struct PPKeepBlock: View {
    let m: PPMechanism
    let unit: PPMechanismPage.Unit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("keep".uppercased())
                .font(PP.mono(11)).tracking(11 * 0.2)
                .foregroundStyle(PP.paperText)
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(headline)
                    .font(PP.disp(52, .semibold)).tracking(52 * -0.04)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                Text(sub).font(PP.disp(17))
                    .foregroundStyle(PP.paperText)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Text(detail).font(PP.disp(15)).lineSpacing(15 * 0.35)
                .foregroundStyle(PP.paperText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private var headline: String {
        switch unit {
        case .delta:  return m.keepPct.map { "\(Int($0))%" } ?? "—"
        case .shares: return m.freeShares.map(grouped) ?? "—"
        }
    }
    private var sub: String {
        switch unit {
        case .delta:  return "of your delta"
        case .shares: return "shares uncapped"
        }
    }
    private var detail: String {
        switch unit {
        case .delta:
            guard let k = m.keepDelta, let t = m.totalDelta else { return "" }
            return "\(grouped(k)) of \(grouped(t)) delta stays yours"
                 + (m.soldDelta.map { ". \(grouped($0)) is what gets sold." } ?? ".")
        case .shares:
            guard let c = m.coveredShares, let t = m.totalDelta else { return "" }
            return "\(grouped(c)) of \(grouped(t)) shares are capped"
                 + (m.contracts.map { " across \($0) contracts." } ?? ".")
        }
    }
}

/// The confirm. A mechanism confirms the same way a chosen panel did — by naming
/// the exact trade in words before the button will move. What is recorded is the
/// TRADE, never the two numbers that produced it: the numbers change tomorrow,
/// the contract does not.
private struct PPMechConfirm: View {
    let m: PPMechanism
    let commit: PPCommit?
    @Binding var ticked: Bool
    let fire: () -> Void

    private var line: String {
        "\(m.contracts ?? 0) at \(f2(m.strike ?? 0))"
            + (m.expiry.map { ", \(PPMechanismPage.day($0))" } ?? "")
    }
    private var isLive: Bool {
        guard let c = commit else { return false }
        return c.strike == m.strike && c.ct == m.contracts && c.expiry == m.expiry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLive, let c = commit {
                HStack(alignment: .top, spacing: 11) {
                    box(true)
                    Text("Executed \(line). Logged \(c.onLabel).")
                        .font(PP.disp(14)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 16)
            } else {
                Button { ticked.toggle() } label: {
                    HStack(alignment: .top, spacing: 11) {
                        box(ticked)
                        Text("This is what is executed: \(line).")
                            .font(PP.disp(14)).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain).padding(.top, 16)
                Button(action: fire) {
                    HStack {
                        Text((commit == nil ? "start monitoring" : "replace the position").uppercased())
                        Spacer()
                    }
                    .font(PP.mono(13)).tracking(13 * 0.06)
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
