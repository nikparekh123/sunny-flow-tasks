//
//  SunnyPageHead.swift
//  Sunny — a name page's heading and its two figures. SHELL-PAGED.md §5.
//
//  Two pane children, never one: the heading, then the figures. They are
//  separate so a filed card can land between the figures and the page's
//  resident cards, which is where a thing that just arrived belongs.
//

import SwiftUI

// MARK: - the heading, 57pt

struct SunnyPageHead: View {
    let ticker: String
    let name: String
    let weight: Int

    var body: some View {
        HStack(spacing: S.gap6) {
            /* The same circle as the strip, one size down and always at rest —
               it names the page you are on, so it carries no state of its own. */
            Text(ticker)
                .font(S.inter(S.t10, S.wBoldN))
                .tracking(S.track(S.t10, 0.02))
                .foregroundStyle(S.mute)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: S.shellHeadMark, height: S.shellHeadMark)
                .overlay(Circle().strokeBorder(S.shellHair, lineWidth: S.shellRingRest))

            VStack(alignment: .leading, spacing: 1) {
                /* ⚠ THE COMPANY NAME MUST ELLIPSIZE. Polygon returns "Alibaba
                   Group Holding Limited American Depositary Shares, each
                   represents eight Ordinary Shares" for BABA, which overflows
                   361 several times over. */
                Text(name.isEmpty ? ticker : name)
                    .font(S.inter(S.t22, S.wSemiN))
                    .tracking(S.track(S.t22, -0.025))
                    .foregroundStyle(S.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(weight)% of the book")
                    .font(S.inter(S.t12, S.wMidSmN))
                    .foregroundStyle(S.mute2)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: S.content, alignment: .leading)
        .padding(.top, S.gap6)
        .padding(.bottom, S.gap1)
        .measure("pagehead")
    }
}

// MARK: - the two figures, 42pt

/// ⚠ TWO COLUMNS, NEVER THREE. A third — today, or unrealised — makes the row a
/// table and the heading stops being a heading.
///
/// ⚠ THEY DISAGREE ON PURPOSE, and that is the whole reason both are shown. NKE
/// prints −$2,570 current against −$6,675 total: what two years of writing
/// premium against a position that is currently underwater looks like.
///
///   Current  what the open position is worth against its basis right now.
///            docs/PNL_GLOSSARY.md calls this UNREALIZED, and it is the five leg
///            cards summed — so the heading and the cards under it can never
///            disagree. If they ever do, one of the two numbers is wrong.
///   Total    every dollar the name has made or lost, all time. The glossary
///            calls this NET: REALIZED + UNREALIZED.
struct SunnyPageFigures: View {
    let current: Int?
    let total: Int?

    var body: some View {
        HStack(spacing: 0) {
            column("Current", current, padLeft: 0)
            Rectangle().fill(S.shellHair).frame(width: 1)
            column("Total", total, padLeft: S.gap7)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: S.content)
        .padding(.top, S.gap1)
        .padding(.bottom, S.gap2)
        .measure("pagefigs")
    }

    private func column(_ label: String, _ v: Int?, padLeft: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(S.inter(S.t10, S.wBoldN))
                .tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
            /* A name whose figure has not landed yet prints an em dash, never a
               zero: a zero claims the position is flat, which is a statement
               about the book rather than about the fetch. */
            Text(v.map(signed) ?? "\u{2014}")
                .font(S.inter(S.t19, S.wBoldN))
                .tracking(S.track(S.t19, -0.025))
                .foregroundStyle(v == nil ? S.mute2 : (v! < 0 ? S.loss : S.gain))
                .monospacedDigit()
                .sunnyLineBox(S.t19)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, padLeft)
    }
}

// MARK: - the New page's heading

struct SunnyNewHead: View {
    let due: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.headingGap) {
            Text("On a clock")
                .font(S.inter(S.t22, S.wSemiN))
                .tracking(S.track(S.t22, -0.025))
                .foregroundStyle(S.ink)
            Text(due == 1 ? "1 card due" : "\(due) cards due")
                .font(S.inter(S.t12, S.wMidSmN))
                .foregroundStyle(S.mute2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: S.content, alignment: .leading)
        .padding(.top, S.gap6)
        .padding(.bottom, S.gap1)
        .measure("newhead")
    }
}

// MARK: - the New page's figures

/// The same treatment as a name page's Current / Total, on the book's open short
/// options. Nik: "just how we have current and total on top for each ticker we
/// should do that to featured."
///
/// ⚠ THREE COLUMNS, AND THAT DEPARTS FROM SHELL-PAGED §5, which says two and
/// never three because a third "makes the row a table and the heading stops
/// being a heading". That rule was written about the NAME page's P&L block,
/// where the third candidate was a redundant restatement (today, or unrealised).
/// Here the three are genuinely different quantities and Nik named all three. If
/// it reads as a table on a real screen the fix is a design prompt, not a
/// silent drop of one figure.
///
/// ⚠ NO DIRECTION INK. A credit, a value and a time value are balances, not
/// directions, and the deck reserves colour for direction. All three are --ink.
struct SunnyShortFigures: View {
    let s: OpenShorts

    var body: some View {
        HStack(spacing: 0) {
            column("Credit open", s.credit, padLeft: 0)
            Rectangle().fill(S.shellHair).frame(width: 1)
            column("Time value", s.time_value, padLeft: S.gap7)
            Rectangle().fill(S.shellHair).frame(width: 1)
            column("Value left", s.value, padLeft: S.gap7)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: S.content)
        .padding(.top, S.gap1)
        .padding(.bottom, S.gap2)
        .measure("shortfigs")
    }

    private func column(_ label: String, _ v: Int, padLeft: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(S.inter(S.t10, S.wBoldN))
                .tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
                .lineLimit(1)
            Text("$" + abs(v).formatted(.number.grouping(.automatic)))
                .font(S.inter(S.t19, S.wBoldN))
                .tracking(S.track(S.t19, -0.025))
                .foregroundStyle(S.ink)
                .monospacedDigit()
                .sunnyLineBox(S.t19)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, padLeft)
    }
}

// MARK: - an honest empty page

/// 15px at weight 300, which clears the 14px floor by one step. A page with no
/// card says so in a sentence rather than showing a blank column.
struct SunnyPageNote: View {
    let text: String
    init(_ t: String) { text = t }

    var body: some View {
        Text(text)
            .font(S.inter(S.tDigestBody, S.wLightN))
            .lineSpacing(S.tDigestBody * (S.lhDigest - 1))
            .foregroundStyle(S.shellEmptyInk)
            .frame(width: S.content, alignment: .leading)
            .padding(.top, S.gap1)
            .padding(.bottom, S.gap3)
    }
}
