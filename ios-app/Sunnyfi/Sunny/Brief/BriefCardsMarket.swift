//
//  BriefCardsMarket.swift
//  Sunny
//
//  Section 1 of New Home (README 5.2): the index cards (live, implied by futures, or the week), the overnight
//  markets and the world this week, the economy and today's releases, sectors with their 11 heat maps, and the
//  Your names / Watchlist maps that open section 2. Market cards stay the same on an account switch.
//

import SwiftUI

// MARK: - Index cards (SPY QQQ IWM VIX; futures badges ES NQ RTY VX)

/// The design's sizes for section 1 (SunnyBriefs index cards, SunnyEconomy shelf cards).
enum BMk {
    /// A shelf card's inside: 341 wide less 20 a side on a 402 phone; the card is the screen less 61, so the next card
    /// still peeks 29 pt at 375 and 440 (Audit 1: a fixed 341 left no peek at 375, the only sign the row scrolls).
    static let shelfW: CGFloat = MainActor.assumeIsolated {
        let w = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 402
        return max(240, w - 61 - 40)
    }
    /// Content heights inside the 20 shell, plus the 2 the design's 18 top padding gives back.
    static let econH: CGFloat = 392 - 40 + 2
    static let mapH: CGFloat = 268 - 40 + 2
    static let label = SType(size: 15, weight: 500, line: 20, tracking: 0)
    static let big = SType(size: 34, weight: 700, line: 38, tracking: -0.02)
    static let mapTitle = SType(size: 17, weight: 600, line: 22, tracking: 0)
}

struct BIndexRow: View {
    let card: JSONValue
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BRow(spacing: 8) {
                ForEach(Array(card["cards"].array.enumerated()), id: \.offset) { _, c in
                    VStack(alignment: .leading, spacing: 0) {
                        // The label row is 15 tall; the 18 badge overhangs it evenly.
                        HStack(spacing: 4) {
                            Text(c["symbol"].string ?? "").sType(SType(size: 15, weight: 500, line: 15, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            Spacer(minLength: 0)
                            if let b = c["badge"].string {
                                Text(b).sType(SType(size: 11, weight: 700, line: 11, tracking: 0), tabular: false).foregroundStyle(S.badgeInk)
                                    .fixedSize()   // never "R…": the HStack would hand it a third of the row first
                                    .padding(.horizontal, 6).frame(height: 18)
                                    .background(Capsule().fill(S.yellow))
                            }
                        }
                        .frame(height: 15)
                        Spacer(minLength: 0)
                        Text(c["price"].string ?? "").sType(SType(size: 15, weight: 700, line: 15, tracking: 0)).foregroundStyle(S.ink)
                        BMove(text: c["move"].string, color: c["moveColor"].string, signed: c["moveSigned"].double,
                              type: SType(size: 15, weight: 700, line: 15, tracking: 0))
                            .padding(.top, 8)
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)   // only at the largest text sizes: 75 across
                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 105)
                    .briefCard(radius: 16, padding: 20)
                    // Three across the page: (width less the two 20 gutters and two 8 gaps) / 3, a fourth peeking.
                    .containerRelativeFrame(.horizontal) { w, _ in (w - 2 * S.margin - 16) / 3 }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(c["aria"].string ?? "")
                }
            }
            BFooter(v: card["footer"], type: SType(size: 13, weight: 500, line: 16, tracking: 0)).padding(.horizontal, S.margin)
        }
    }
}

// MARK: - Overnight markets and the world this week

struct BMarketsCard: View {
    let card: JSONValue
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card["title"].string ?? "").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer(minLength: 0)
                BSub(t: card["subtitle"].string).lineLimit(1)
            }
            .padding(.bottom, 12)   // 16 to the list, less its 4 pull-up
            ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { i, r in
                if i > 0 { BHairline() }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r["name"].string ?? "").bLine(BK.row, tabular: false).foregroundStyle(S.ink)
                        Text(r["sub"].string ?? "").bLine(BK.sub, tabular: false).foregroundStyle(S.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(r["value"].string ?? "").bLine(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                        BMove(text: r["move"].string, color: r["moveColor"].string, type: SType(size: 13, weight: 700, line: 16, tracking: 0))
                    }
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(r["aria"].string ?? "")
            }
            if let f = card["footer"].string {
                Text(f).sType(SType(size: 12, weight: 500, line: 15, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    .padding(.top, 14)   // 16, less the list's 2 pull-up
            }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - The economy, and today's releases

/// One indicator card (SunnyEconomy, 341 × 392): label and tag, the reading big, its trend, four bars (the latest
/// dark) with their dates, a rule and the note.
struct BIndicatorCard: View {
    let c: JSONValue
    /// The shelf card's inside (301); nil fills the width (the economy sheet).
    var width: CGFloat? = BMk.shelfW
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(c["label"].string ?? c["name"].string ?? "").sType(BMk.label, tabular: false).foregroundStyle(S.secondary)
                    .fixedSize(horizontal: false, vertical: true)   // wraps before the tag is cut (Pass 5)
                Spacer(minLength: 0)
                if let tag = c["tag"].string {
                    let yellow = c["tagStyle"].string == "yellow"
                    HStack(spacing: 5) {
                        if yellow {
                            Image(systemName: "eye").font(.system(size: 11, weight: .semibold))
                                .frame(width: 14, height: 14).accessibilityHidden(true)
                        }
                        Text(tag).sType(SType(size: 12, weight: 600, line: 12, tracking: 0), tabular: false)
                    }
                        .foregroundStyle(yellow ? S.badgeInk : S.ink)
                        .padding(.horizontal, 9).frame(minHeight: 24)
                        .fixedSize()
                        .background(Capsule().fill(yellow ? S.yellow : .clear))
                        .overlay(Capsule().strokeBorder(yellow ? .clear : S.ink, lineWidth: 1.5))
                }
            }
            .frame(minHeight: 24)
            Text(c["value"].string ?? "").sType(BMk.big).foregroundStyle(S.ink)
                .padding(.top, 10)
            HStack(alignment: .top, spacing: 6) {
                Text(c["arrow"].string ?? "").fixedSize().frame(width: 14).accessibilityHidden(true)
                Text(c["trend"].string ?? "").fixedSize(horizontal: false, vertical: true)
            }
            .sType(BMk.label, tabular: false).foregroundStyle(S.ink)
            .padding(.top, 4)
            let pts = c["chart"]["points"].array
            if !pts.isEmpty {
                // SunnyEconomy bars: 34 to 64 tall across the four readings (60 when flat), rounded on top, the
                // reading 4 above its bar, the date 6 under the 100 tall chart.
                let vals = pts.map { $0["value"].double ?? 0 }
                let lo = vals.min() ?? 0, hi = vals.max() ?? 0
                VStack(spacing: 6) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(pts.enumerated()), id: \.offset) { i, p in
                            let cur = p["current"].bool
                            let h: CGFloat = hi == lo ? 60 : (34 + 30 * CGFloat((vals[i] - lo) / (hi - lo))).rounded()
                            VStack(spacing: 4) {
                                Text(p["value"].string ?? "").sType(SType(size: 13, weight: cur ? 700 : 500, line: 16, tracking: 0))
                                    .foregroundStyle(cur ? S.ink : S.secondary)
                                    .lineLimit(1).fixedSize()
                                UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5, style: .circular)
                                    .fill(cur ? S.ink : width == nil ? S.econBar : S.econBarGlass)
                                    .frame(height: h)
                                    .padding(.horizontal, 4)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 100, alignment: .bottom)
                    HStack(spacing: 0) {
                        ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                            Text(p["label"].string ?? "").sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                                .foregroundStyle(S.secondary).lineLimit(1).fixedSize()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, -4)
                .padding(.top, 18)
                // The four bars as one spoken line: the content's own chartAria, else "<name>: Oct 16 3.31, ...".
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(c["chartAria"].string ?? BSay.join([c["label"].string ?? c["name"].string,
                    pts.map { BSay.join([$0["label"].string, $0["value"].string], " ") }.joined(separator: ", ")], ": "))
            }
            if let n = c["note"].string {
                BHairline().padding(.top, 16)
                Text(n).sType(SType(size: 15, weight: 400, line: 21, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .frame(minHeight: BMk.econH, alignment: .top)
        .padding(.top, -2)   // the design's 18 top padding inside the 20 shell
        .modifier(BIndicatorChrome(sheet: width == nil))
        .accessibilityElement(children: .combine)
    }
}

/// Glass on Home; on the economy sheet the design's solid card: paper, a 1 pt outline, radius 16.
private struct BIndicatorChrome: ViewModifier {
    let sheet: Bool
    func body(content: Content) -> some View {
        if sheet {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            content
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shape.fill(S.paper))
                .overlay(shape.strokeBorder(S.line, lineWidth: 1))
        } else {
            content.briefCard()
        }
    }
}

/// A summary row's dot: yellow when worth watching, else an ink ring.
private struct BWatchDot: View {
    let on: Bool
    var body: some View {
        Circle().fill(on ? S.yellow : .clear)
            .overlay(Circle().strokeBorder(on ? .clear : S.ink, lineWidth: 1.5))
            .frame(width: 8, height: 8)
            .frame(width: 10, alignment: .leading)
    }
}

struct BEconomyRow: View {
    let card: JSONValue
    @Environment(BriefState.self) private var brief
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BRow {
                VStack(alignment: .leading, spacing: 0) {
                    Text(card["label"].string ?? "The economy").sType(BMk.label, tabular: false).foregroundStyle(S.secondary)
                        .frame(minHeight: 24)
                    Text(card["headline"].string ?? "").sType(BMk.big).foregroundStyle(S.ink)
                        .padding(.top, 10)
                    Text(card["sub"].string ?? "").sType(BMk.label, tabular: false).foregroundStyle(S.ink)
                        .padding(.top, 4)
                    BHairline().padding(.top, 12)
                    let watching = Set(card["indicators"].array.filter { $0["tagStyle"].string == "yellow" }.compactMap { $0["name"].string })
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { i, r in
                            let on = watching.contains(r["name"].string ?? "") || (watching.isEmpty && i < 3)
                            // Dot, name and value on one line; the trend under the name, running under the value too.
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(alignment: .center, spacing: 8) {
                                    BWatchDot(on: on)
                                    Text(r["name"].string ?? "").bLine(BK.row, tabular: false).foregroundStyle(S.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(r["value"].string ?? "").bLine(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                                }
                                Text(r["trend"].string ?? "").bLine(SType(size: 13, weight: 500, line: 17, tracking: 0), tabular: false)
                                    .foregroundStyle(S.secondary)
                                    .padding(.leading, 18)
                            }
                            // The yellow dot in words: one stop per row, "watching" on the ones worth watching.
                            .accessibilityElement(children: .combine)
                            .accessibilityValue(on ? "watching" : "")
                        }
                    }
                    .padding(.top, 12)
                    Spacer(minLength: 0)
                }
                .frame(width: BMk.shelfW, alignment: .leading)
                .frame(minHeight: BMk.econH, alignment: .top)
                .padding(.top, -2)
                .briefCard()
                ForEach(Array(card["indicators"].array.enumerated()), id: \.offset) { _, c in BIndicatorCard(c: c) }
            }
            if let b = card["button"].string {
                Button { brief.sheet = .economy } label: {
                    HStack(spacing: 4) {
                        Text(b).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).frame(width: 12, height: 12)
                    }
                    .foregroundStyle(S.ink)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(b)
                .padding(.top, -4)   // 44 tall, 4 into the shelf's gap
                .padding(.horizontal, S.margin)
            }
        }
    }
}

struct BOutToday: View {
    let card: JSONValue
    var body: some View {
        BRow { ForEach(Array(card["indicators"].array.enumerated()), id: \.offset) { _, c in BIndicatorCard(c: c) } }
    }
}

// MARK: - Sectors and their maps

/// The design's chevron on a Leads or Trails row (8 × 13, a 1.8 stroke).
private struct BRowChevron: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 1.5, y: 1.5)); p.addLine(to: CGPoint(x: 6.5, y: 6.5)); p.addLine(to: CGPoint(x: 1.5, y: 11.5))
        }
        .stroke(S.secondary, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        .frame(width: 8, height: 13)
        .accessibilityHidden(true)
    }
}

/// A map card's top line: the title, then the period ("Week") and the move, 17/22 semibold.
private struct BMapHead: View {
    let page: JSONValue
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Wraps at the largest text sizes rather than cut "Your names" short (Audit 6); one line at normal size.
            Text(page["title"].string ?? "").sType(BMk.mapTitle, tabular: false).foregroundStyle(S.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let per = page["period"].string {
                    Text(per).sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
                }
                BMove(text: page["move"].string, color: page["moveColor"].string, type: BMk.mapTitle,
                      tri: CGSize(width: 12, height: 9), gap: 6)
            }
            .fixedSize()
        }
        .frame(minHeight: 24)
    }
}

/// A map card (341 × 268): the head, then the 305 × 196 map reaching 2 past the padding on three sides.
private struct BMapCard: View {
    let page: JSONValue
    /// Spoken with the title: the sector's share of the S&P 500 (not shown, as in the design).
    var weight: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BMapHead(page: page)
                // "Technology, 34% of the S&P 500, up 1.83%": the triangle speaks as a word (BMove).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BSay.join([page["title"].string, weight.map { "\($0) of the S&P 500" },
                                               BSay.move(page["move"].string, color: page["moveColor"].string),
                                               page["period"].string]))
                .accessibilityAddTraits(.isHeader)
            BHeatMap(page: page)
                .padding(.horizontal, -2)
                .padding(.bottom, -2)
                .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .frame(width: BMk.shelfW, alignment: .leading)
        .frame(minHeight: BMk.mapH, alignment: .top)
        .padding(.top, -2)
        .briefCard()
    }
}

struct BSectorsRow: View {
    let card: JSONValue
    @Environment(\.dynamicTypeSize) private var dts

    /// A Leads or Trails row spoken: the content's aria ("Leads: Technology, up 1.83%"), else built from the row.
    static func rowSays(_ r: JSONValue) -> String {
        if let a = r["aria"].string {
            return a.replacingOccurrences(of: #"\.?\s*Show its map\.?$"#, with: "", options: .regularExpression)
        }
        return "\(r["label"].string ?? ""): " + BSay.join([r["sector"].string, BSay.move(r["move"].string, color: r["moveColor"].string)])
    }

    var body: some View {
        // The server sends its 11 maps on the card; the sample keeps them once per period.
        let maps = card["maps"].isNull ? BriefSample.sectorMaps(card["mapsRef"].string ?? "day").array : card["maps"].array
        BRow {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(card["label"].string ?? "Sectors").sType(BMk.label, tabular: false).foregroundStyle(S.secondary)
                    Spacer(minLength: 0)
                    Text(card["count"].string ?? "").sType(BK.sub, tabular: false).foregroundStyle(S.secondary).lineLimit(1)
                }
                .frame(minHeight: 24)
                Text(card["writeUp"].array.compactMap(\.string).joined(separator: " "))
                    .sType(SType(size: 17, weight: 400, line: 25, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    .lineLimit(dts > .large ? nil : 3).fixedSize(horizontal: false, vertical: true)   // all of it at large text (Audit 6)
                    .padding(.top, 12)
                Spacer(minLength: 0)
                // Leads and Trails pinned to the bottom: a rule above, rows 48 tall, a rule between them.
                VStack(alignment: .leading, spacing: 0) {
                    BHairline()
                    ForEach(Array(card["leadsTrails"].array.enumerated()), id: \.offset) { i, r in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(r["label"].string ?? "").sType(SType(size: 12, weight: 600, line: 15, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                                Text(r["sector"].string ?? "").sType(BK.row, tabular: false).foregroundStyle(S.ink)
                            }
                            .lineLimit(dts > .large ? nil : 1).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            BMove(text: r["move"].string, color: r["moveColor"].string, type: SType(size: 15, weight: 700, line: 20, tracking: 0),
                                  tri: CGSize(width: 10, height: 8), gap: 6)
                            BRowChevron()
                        }
                        .padding(.vertical, 4)
                        .frame(minHeight: 48)
                        .overlay(alignment: .top) { if i > 0 { BHairline() } }
                        // The row's own aria, less its "Show its map" (the row does nothing on a tap, so no button trait).
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.rowSays(r))
                    }
                }
            }
            .frame(width: BMk.shelfW, alignment: .leading)
            .frame(minHeight: BMk.mapH, alignment: .top)
            .padding(.top, -2)
            .briefCard()
            ForEach(Array(maps.enumerated()), id: \.offset) { _, m in
                BMapCard(page: m, weight: m["weightOfSP500"].string)
            }
        }
    }
}

// MARK: - Your names and the watchlist (two maps)

struct BNamesRow: View {
    let card: JSONValue
    var body: some View {
        BRow {
            ForEach(Array(card["pages"].array.enumerated()), id: \.offset) { _, p in BMapCard(page: p) }
        }
    }
}
