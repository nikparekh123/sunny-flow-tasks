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

// MARK: - the expand chip

/// ⚠ THE 44pt TARGET IS REACHED BY OVERHANG, NEVER BY PADDING THE LABEL.
/// Padding to 44 pushes the text off grid — the same recipe CHROME.md §5 fixes
/// with a ::before. In SwiftUI that is a `contentShape` on a taller frame.
struct SunnyExpandChip: View {
    let label: String
    let tap: () -> Void

    var body: some View {
        Text(label.uppercased())
            .font(S.inter(S.t11, S.wSemiN))
            .tracking(S.track(S.t11, S.lsNew))
            .foregroundStyle(S.mute)
            .sunnyLineBox(S.t11)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(S.hair, lineWidth: 1))
            .frame(height: S.hitMin)
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
    }
}

// MARK: - a link row

/// ⚠ THE HEADLINE IS THE LINK, EVERYWHERE. No teaser we did not receive, no
/// summary we wrote, no sentiment we cannot compute — the feed ships a title
/// and a url, and the url is what is being paid for.
struct SunnyLinkRow: View {
    let l: NewsLink

    var body: some View {
        Link(destination: URL(string: l.url) ?? URL(string: "https://polygon.io")!) {
            VStack(alignment: .leading, spacing: S.gap2) {
                (Text(l.title) + Text("  \u{2197}").foregroundColor(S.mute2))
                    .font(S.inter(S.t15, S.wMidSmN))
                    .foregroundStyle(S.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(l.publisher) \u{00B7} \(ago(l.hours))")
                    .font(S.inter(S.t13, S.wMidSmN))
                    .foregroundStyle(S.mute2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
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

// MARK: - the filtered list

/// ⚠ EVERY EXPANDED ROW NAMES WHY THE ITEM WAS HELD BACK. A filtered list that
/// does not say why is a second silent gate — the count already told him
/// something was withheld.
struct SunnyFilteredList: View {
    let rows: [NewsBlock.Filtered.Row]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 { Rectangle().fill(S.ruleColor).frame(height: 1) }
                Link(destination: URL(string: r.url) ?? URL(string: "https://polygon.io")!) {
                    VStack(alignment: .leading, spacing: S.gap2) {
                        Text(r.title)
                            .font(S.inter(S.t14, S.wMidSmN))
                            .foregroundStyle(S.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(r.ticker) \u{00B7} \(r.reason ?? "held back")")
                            .font(S.inter(S.t13, S.wMidSmN))
                            .foregroundStyle(S.mute2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, S.t13)
                }
                .buttonStyle(.plain)
            }
        }
        .measure("filtered-list")
    }
}
