//
//  SunnyNewChrome.swift
//  Sunny — the New page's chrome. NEW-PAGE.md §3–§7.
//
//  The title row, the date row, the seams, the expand chips and the empty
//  states. None of this is a card, and none of it restyles one.
//

import SwiftUI

// MARK: - the title row

/// ⚠ THE HEADER DATE IS A DAY, NEVER A WEEK RANGE. The page runs on two clocks
/// and the lead is today's; putting both under one "week to 26 Aug" made three
/// news items look like a slow week rather than a normal day.
struct SunnyNewTitle: View {
    let date: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap5) {
            Text("New")
                .font(S.inter(S.t22, S.wSemiN))
                .tracking(S.track(S.t22, -0.025))
                .foregroundStyle(S.ink)
            Spacer(minLength: 0)
            Text(longDate(date))
                .font(S.inter(S.t13, S.wMidSmN))
                .foregroundStyle(S.mute2)
        }
        .padding(.top, S.gap4)
        .measure("new-title")
    }
}

/// The same device as `SunnyNewTitle`, for a page whose right-hand fact is not
/// a date. Kept separate rather than making the date optional: the New page's
/// title always has one, and an optional there would let a future edit ship a
/// New page with no date and no error.
struct SunnyPageTitle: View {
    let title: String
    let note: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap5) {
            Text(title)
                .font(S.inter(S.t22, S.wSemiN))
                .tracking(S.track(S.t22, -0.025))
                .foregroundStyle(S.ink)
            Spacer(minLength: 0)
            Text(note)
                .font(S.inter(S.t13, S.wMidSmN))
                .foregroundStyle(S.mute2)
        }
        .padding(.top, S.gap4)
        .measure("page-title")
    }
}

// MARK: - the date row

/// ⚠ THE ONLY FORWARD-LOOKING BLOCK ON THE PAGE — everything below it has
/// already happened — and the only amber above the fold. The COUNTDOWN is the
/// figure and the event is the label, never the reverse.
struct SunnyDateRow: View {
    let dates: [NewEarningsDate]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: S.gapDateRow) {
                ForEach(dates) { d in
                    let soon = d.days <= S.dateWarnDays
                    HStack(spacing: S.gapPillDate) {
                        Text("\(d.days) \(d.days == 1 ? "day" : "days")")
                            .font(S.inter(S.tPillFigure, S.wSemiN))
                            .tracking(S.track(S.tPillFigure, -0.01))
                            .foregroundStyle(soon ? S.warnText : S.ink)
                            .sunnyLineBox(S.tPillFigure)
                        Text(d.label)
                            .font(S.inter(S.tPillLabel, S.wMidSmN))
                            .foregroundStyle(soon ? S.warnText : S.mute)
                            .sunnyLineBox(S.tPillLabel)
                    }
                    .padding(S.padPillDate)
                    .background(soon ? S.warnWash : S.wash)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, S.margin)
        }
        .scrollIndicators(.hidden)
        /* Full bleed: the row scrolls past the pane's own 16, so a pill can sit
           at the frame edge rather than stopping short of it. */
        .padding(.horizontal, -S.margin)
        .padding(.top, 2)
        .padding(.bottom, S.gap6)
        .measure("date-row")
    }
}

// MARK: - the seam

/// ⚠ SEAMS EXIST ONLY WHERE TWO SECTIONS NEED TELLING APART. News carries none:
/// a 26/300 headline under the date row is self-evidently news, and a heading
/// over the first block on a page is a partition with nothing on the other side.
///
/// ⚠ THE COUNT IS PART OF THE SEAM AND PRINTS 0. It is not hidden when the
/// section is empty — that is the difference between a quiet feed and a broken
/// one.
struct SunnySeam: View {
    let label: String
    let count: Int?
    var note: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: S.seamGap) {
            /* The strip circle's left rhythm, so a seam label starts where a
               page heading's mark would. */
            Color.clear.frame(width: S.seamIndent, height: 1)
            Text(label)
                .font(S.inter(S.t13, S.wSemiN))
                .tracking(S.track(S.t13, -0.01))
                .foregroundStyle(S.ink)
            if let count {
                Text("\(count)")
                    .font(S.inter(S.t13, S.wMidSmN))
                    .foregroundStyle(S.mute2)
                    .monospacedDigit()
            }
            if let note {
                Text(note)
                    .font(S.inter(S.t13, S.wMidSmN))
                    .foregroundStyle(S.mute2)
            }
            /* ⚠ --rule-color-strong, NOT --rule-color: #E7E9E5 disappears
               against the --ground pane. */
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
        }
        .padding(S.padSeam)
        .measure("seam")
    }
}

// MARK: - empty-section prose

/// ⚠ AN EMPTY SECTION STATES ITS LAST DATE. Without one, an empty feed and a
/// broken feed are indistinguishable. Prose, not a card — a card would give
/// emptiness the same weight as a fact.
struct SunnyEmptyNote: View {
    let line: String
    let last: String?

    var body: some View {
        VStack(alignment: .leading, spacing: S.gap2) {
            Text(line)
                .font(S.inter(S.t15, S.wMidSmN))
                .foregroundStyle(S.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let last {
                Text(last)
                    .font(S.inter(S.t13, S.wMidSmN))
                    .foregroundStyle(S.mute2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, S.gap2)
    }
}

// MARK: - formatting

/// Ingest is hourly, so the age prints in hours. A ticking "just now" writes a
/// promise the pipeline cannot keep.
func ago(_ hours: Int) -> String {
    if hours < 1 { return "just in" }
    if hours < 24 { return "\(hours) \(hours == 1 ? "hour" : "hours") ago" }
    let d = hours / 24
    return "\(d) \(d == 1 ? "day" : "days") ago"
}

/// `2026-08-29` → `Saturday 29 August`. The header date is a DAY.
func longDate(_ iso: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "America/New_York")
    guard let d = f.date(from: iso) else { return iso }
    let o = DateFormatter()
    o.dateFormat = "EEEE d MMMM"
    o.timeZone = f.timeZone
    return o.string(from: d)
}

/// `2026-09-17` → `17 Sep`.
func shortDate(_ iso: String) -> String {
    let p = iso.split(separator: "-")
    guard p.count == 3 else { return iso }
    return "\(Int(p[2]) ?? 0) \(expShort(iso).split(separator: " ").first.map(String.init) ?? "")"
}
