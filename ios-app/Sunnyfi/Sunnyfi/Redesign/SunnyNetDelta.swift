//
//  SunnyNetDelta.swift
//  Sunny — net delta. net-delta.md (the list) and net-delta-single.md (the card).
//
//  The tile grid goes on New each morning; ONE card per ticker sits on that
//  name's page. Same pattern as average price.
//
//  ⚠ A POSITIVE DELTA IS NOT A GAIN. Shares long is a direction, not money made,
//  so there is NO GREEN anywhere on either card and none in their token set.
//  Every long figure is --ink at every size; only a short takes colour.
//
//  ⚠ THE FIGURE IS SIGNED, SO THE FIGURE CARRIES THE EXCEPTION. A short's figure
//  takes --loss and its exposure line stays grey. This is the exact inverse of
//  the average price card, whose figure is UNSIGNED and whose READING turns red
//  — same tile, opposite slot. One red slot per tile, never two: a red reading
//  under a red figure says short twice.
//
//  ⚠ NEITHER CARD TAKES A GROUND. Average price washes its whole ground because
//  there the ground IS the reading — a basis has no sign to carry it. Here the
//  sign already is the reading, and a wash would state the same fact a third
//  time.
//

import SwiftUI

// MARK: - the list, a tile grid, on New

struct SunnyNetDeltaList: View {
    let book: [BookName]

    /// ⚠ EXCEPTIONS FIRST, THEN ALPHABETICAL. A grid cannot express a ranking —
    /// you read across, then down — so no sort by size is legible in it, and at
    /// this count none is needed: you are looking a name up, and the shorts are
    /// already marked. A card whose SORT is its answer keeps a ranked list.
    private var names: [(String, BookDelta)] {
        book.compactMap { b in b.delta.map { (b.ticker, $0) } }
            .sorted {
                $0.1.short == $1.1.short ? $0.0 < $1.0 : ($0.1.short && !$1.1.short)
            }
    }
    private var shorts: Int { names.filter(\.1.short).count }

    /// The wide tile takes the last name when the count is odd. A half-width
    /// tile in a full-width slot reads as a rendering fault.
    private var paired: [(String, BookDelta)] {
        names.count % 2 == 0 ? names : Array(names.dropLast())
    }
    private var odd: (String, BookDelta)? {
        names.count % 2 == 1 ? names.last : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: S.tileGap) {
                ForEach(Array(stride(from: 0, to: paired.count, by: 2)), id: \.self) { i in
                    HStack(spacing: S.tileGap) {
                        tile(paired[i])
                        tile(paired[i + 1])
                    }
                }
                if let odd { wideTile(odd) }
            }
            .padding(.horizontal, S.avgPadX)
            Color.clear.frame(height: S.listFoot)
        }
        .frame(width: S.content)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .measure("delta-list")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.gap5) {
            Text("Net delta")
                .font(S.inter(S.t18, S.wLightN))
                .tracking(S.track(S.t18, -0.025))
                .foregroundStyle(S.ink)
            Spacer(minLength: 0)
            /* ⚠ A COUNT, NOT A STATE. With no shorts the element is ABSENT, not
               set to "0 net short". It is the only other red on the card, and it
               agrees with the dots by construction: one dot per short. */
            if shorts > 0 {
                Text("\(shorts) net short".uppercased())
                    .font(S.inter(S.t10, S.wSemiN))
                    .tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.lossText)
                    .sunnyLineBox(S.t10)
            }
        }
        .padding(.top, S.avgHeadTop)
        .padding(.horizontal, S.avgPadX)
        .padding(.bottom, S.deltaHeadBottom)
    }

    // MARK: a tile

    private func tile(_ n: (String, BookDelta)) -> some View {
        VStack(alignment: .leading, spacing: S.tileSlotGap) {
            HStack(spacing: S.gap3) {
                /* On an ordinary tile the dot is ABSENT, not transparent and not
                   a spacer. The name does not shift: the row's own left edge is
                   the padding, so the eye reads the dot as an addition to the
                   row rather than an indent of it. */
                if n.1.short {
                    Circle().fill(S.loss)
                        .frame(width: S.dotException, height: S.dotException)
                }
                Text(n.0.uppercased())
                    .font(S.inter(S.t10, S.wSemiN))
                    .tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute)
                    .sunnyLineBox(S.t10)
            }
            figure(n.1)
            exposure(n.1)
        }
        .padding(S.padTile)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: S.tileH)
        .overlay(RoundedRectangle(cornerRadius: S.radiusTile, style: .continuous)
            .strokeBorder(S.ruleColor, lineWidth: 1))
    }

    /// One line, not a stretched two-line tile: the three slots are the same
    /// three, re-flowed.
    private func wideTile(_ n: (String, BookDelta)) -> some View {
        HStack(spacing: S.wideSlotGap) {
            if n.1.short {
                Circle().fill(S.loss)
                    .frame(width: S.dotException, height: S.dotException)
            }
            Text(n.0.uppercased())
                .font(S.inter(S.t10, S.wSemiN))
                .tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
            figure(n.1)
            exposure(n.1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(S.padTileWide)
        .frame(maxWidth: .infinity)
        .frame(height: S.tileHWide)
        .overlay(RoundedRectangle(cornerRadius: S.radiusTile, style: .continuous)
            .strokeBorder(S.ruleColor, lineWidth: 1))
    }

    /* ⚠ THE UNIT STAYS ON THE LIST. In a grid of six figures a bare +415 beside
       +$40,200 could be dollars, and the two sit in the same tile. */
    private func figure(_ d: BookDelta) -> some View {
        Text("\(signedInt(d.net)) sh")
            .font(S.inter(S.t22, S.wSemiN))
            .tracking(S.track(S.t22, S.lsTight))
            .foregroundStyle(d.short ? S.loss : S.ink)
            .monospacedDigit()
            .sunnyLineBox(S.t22)
            .fixedSize()
    }

    private func exposure(_ d: BookDelta) -> some View {
        Text("\(signedMoney(d.exposure)) exposure")
            .font(S.inter(S.t12, S.wMidSmN))
            .foregroundStyle(S.mute2)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
            .sunnyLineBox(S.t12)
    }
}

// MARK: - one card per ticker

/// ⚠ DIRECTION IS CARRIED TWICE, ON PURPOSE — by the sign and by the word. A
/// minus at 38px is one glyph, and this card has no second chance to say it.
///
/// ⚠ NO UNIT IN THE FIGURE. `sh` lives in the reading line, so the figure is a
/// pure number and holds 38px. The list keeps it because a bare +415 in a grid
/// could be dollars; here the line below says `shares`.
struct SunnyNetDeltaCard: View {
    let ticker: String
    let d: BookDelta

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            /* The two labels are PEERS, deliberately: neither is the card's
               answer, and giving the ticker more weight would make the card
               about the name rather than the number. It is identified by the
               page it sits on. */
            HStack(alignment: .firstTextBaseline, spacing: S.gap3) {
                Text(ticker)
                Spacer(minLength: 0)
                Text("Delta")
            }
            .font(S.inter(S.t10, S.wSemiN))
            .tracking(S.track(S.t10, S.lsLabel))
            .textCase(.uppercase)
            .foregroundStyle(S.mute)
            .sunnyLineBox(S.t10)

            Spacer(minLength: 0)

            /* The sign is part of the figure, not a prefix element — one text
               node, so the tabular figures and the sign share a baseline and a
               tracking. U+2212, never a hyphen: at 38px a hyphen is visibly
               short and reads as a dash. */
            Text(signedInt(d.net))
                .font(S.inter(S.avgFigure, S.wSemiN))
                .tracking(S.track(S.avgFigure, S.lsTighter))
                .foregroundStyle(d.short ? S.loss : S.ink)
                .monospacedDigit()
                .sunnyLineBox(S.avgFigure * S.lhHero)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            /* Three jobs in four words: the unit, the direction in words, and
               `net` to say this is the position summed across legs rather than
               one leg's count. `net` is not droppable — without it the figure is
               ambiguous on any name with more than one leg, which is most.
               --ink-2 and not --mute: it is a reading, not a label. */
            Text(d.short ? "shares short, net" : "shares long, net")
                .font(S.inter(S.t13, S.wMidSmN))
                .foregroundStyle(S.ink2)
                .sunnyLineBox(S.t13 * S.lhRead)
        }
        .padding(S.padCard)
        .frame(width: S.col, height: S.col, alignment: .leading)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCard)
        .measure("delta-card")
    }
}

// MARK: - shared

/// U+2212, never a hyphen.
func signedInt(_ v: Int) -> String {
    (v < 0 ? "\u{2212}" : "+") + abs(v).formatted(.number.grouping(.automatic))
}

func signedMoney(_ v: Int) -> String {
    (v < 0 ? "\u{2212}" : "+") + "$" + abs(v).formatted(.number.grouping(.automatic))
}
