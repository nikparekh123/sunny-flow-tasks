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

struct BIndexRow: View {
    let card: JSONValue
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BRow {
                ForEach(Array(card["cards"].array.enumerated()), id: \.offset) { _, c in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Text(c["symbol"].string ?? "").sFont(15, .semibold).foregroundStyle(S.ink)
                            Spacer(minLength: 0)
                            if let b = c["badge"].string {
                                Text(b).sFont(11, .bold).foregroundStyle(Color(hex: 0x1D1D1F))
                                    .padding(.horizontal, 6).frame(height: 18)
                                    .background(Capsule().fill(S.yellow))
                            }
                        }
                        Spacer(minLength: 24)
                        Text(c["price"].string ?? "").sFont(15, .semibold, mono: true).foregroundStyle(S.ink)
                        BMove(text: c["move"].string, color: c["moveColor"].string, signed: c["moveSigned"].double,
                              type: SType(size: 15, weight: 700, line: 18, tracking: 0))
                    }
                    .frame(width: 92, height: 104, alignment: .leading)
                    .briefCard(radius: 20, padding: 16)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(c["aria"].string ?? "")
                }
            }
            BFooter(v: card["footer"]).padding(.horizontal, S.margin)
        }
    }
}

// MARK: - Overnight markets and the world this week

struct BMarketsCard: View {
    let card: JSONValue
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(card["title"].string ?? "").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                BSub(t: card["subtitle"].string)
            }
            .padding(.bottom, 8)
            ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { i, r in
                if i > 0 { BHairline() }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r["name"].string ?? "").sType(BK.row, tabular: false).foregroundStyle(S.ink)
                        Text(r["sub"].string ?? "").sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(r["value"].string ?? "").sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                        BMove(text: r["move"].string, color: r["moveColor"].string, type: SType(size: 13, weight: 600, line: 16, tracking: 0))
                    }
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(r["aria"].string ?? "")
            }
            if let f = card["footer"].string {
                Text(f).sType(BK.caption, tabular: false).foregroundStyle(S.secondary).padding(.top, 8)
            }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }
}

// MARK: - The economy, and today's releases

/// One indicator card: label and tag, the reading big, its trend, four bars (the latest dark), a note.
struct BIndicatorCard: View {
    let c: JSONValue
    /// 300 in a sideways row; nil fills the width (the economy sheet).
    var width: CGFloat? = 300
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(c["label"].string ?? c["name"].string ?? "").sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    .fixedSize(horizontal: false, vertical: true)   // wraps before the tag is cut (Pass 5)
                Spacer(minLength: 8)
                if let tag = c["tag"].string {
                    let yellow = c["tagStyle"].string == "yellow"
                    HStack(spacing: 4) {
                        if yellow { Image(systemName: "eye").sFont(10, .semibold).accessibilityHidden(true) }
                        Text(tag).sFont(11, .semibold)
                    }
                        .foregroundStyle(yellow ? S.badgeInk : S.ink)
                        .padding(.horizontal, 8).frame(minHeight: 20)
                        .fixedSize()
                        .background(Capsule().fill(yellow ? S.yellow : .clear))
                        .overlay(Capsule().strokeBorder(yellow ? .clear : S.ink, lineWidth: 1))
                }
            }
            Text(c["value"].string ?? "").sType(SType(size: 34, weight: 800, line: 38, tracking: -0.02)).foregroundStyle(S.ink)
            Text("\(c["arrow"].string ?? "") \(c["trend"].string ?? "")").sType(BK.small, tabular: false).foregroundStyle(S.ink)
                .accessibilityLabel(c["trend"].string ?? "")
            let pts = c["chart"]["points"].array
            if !pts.isEmpty {
                let vals = pts.map { $0["value"].double ?? 0 }
                let lo = (vals.min() ?? 0) * 0.9, hi = vals.max() ?? 1
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(pts.enumerated()), id: \.offset) { i, p in
                        let cur = p["current"].bool
                        VStack(spacing: 4) {
                            Text(p["value"].string ?? "").font(.system(size: 11, weight: cur ? .bold : .medium).monospacedDigit())
                                .foregroundStyle(cur ? S.ink : S.secondary)
                            RoundedRectangle(cornerRadius: 3).fill(cur ? S.ink : width == nil ? S.econBar : S.econBarGlass)
                                .frame(height: 20 + 40 * CGFloat((vals[i] - lo) / max(hi - lo, 0.0001)))
                            Text(p["label"].string ?? "").font(.system(size: 11, weight: .medium)).foregroundStyle(S.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
                // The four bars as one spoken line: the content's own chartAria, else "<name>: Oct 16 3.31, ...".
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(c["chartAria"].string ?? BSay.join([c["label"].string ?? c["name"].string,
                    pts.map { BSay.join([$0["label"].string, $0["value"].string], " ") }.joined(separator: ", ")], ": "))
            }
            if let n = c["note"].string {
                BHairline().padding(.vertical, 4)
                Text(n).sType(BK.body, tabular: false).foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .frame(minHeight: width == nil ? nil : 300, alignment: .top)
        .briefCard()
        .accessibilityElement(children: .combine)
    }
}

struct BEconomyRow: View {
    let card: JSONValue
    @Environment(BriefState.self) private var brief
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BRow {
                VStack(alignment: .leading, spacing: 6) {
                    Text(card["label"].string ?? "The economy").sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    Text(card["headline"].string ?? "").sType(SType(size: 34, weight: 800, line: 38, tracking: -0.02)).foregroundStyle(S.ink)
                    Text(card["sub"].string ?? "").sType(BK.small, tabular: false).foregroundStyle(S.ink)
                    BHairline().padding(.vertical, 4)
                    let watching = Set(card["indicators"].array.filter { $0["tagStyle"].string == "yellow" }.compactMap { $0["name"].string })
                    ForEach(Array(card["rows"].array.enumerated()), id: \.offset) { i, r in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            let on = watching.contains(r["name"].string ?? "") || (watching.isEmpty && i < 3)
                            Circle().fill(on ? S.yellow : .clear).overlay(Circle().strokeBorder(on ? .clear : S.ink, lineWidth: 1.2))
                                .frame(width: 8, height: 8).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r["name"].string ?? "").sType(BK.row, tabular: false).foregroundStyle(S.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(r["trend"].string ?? "").sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Text(r["value"].string ?? "").sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                        }
                        .padding(.vertical, 3)
                        // The yellow dot in words: one stop per row, "watching" on the ones worth watching.
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(watching.contains(r["name"].string ?? "") || (watching.isEmpty && i < 3) ? "watching" : "")
                    }
                }
                .frame(width: 300, alignment: .leading)
                .frame(minHeight: 300, alignment: .top)
                .briefCard()
                ForEach(Array(card["indicators"].array.enumerated()), id: \.offset) { _, c in BIndicatorCard(c: c) }
            }
            if let b = card["button"].string {
                Button { brief.sheet = .economy } label: {
                    Text("\(b) ›").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(b)
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

struct BSectorsRow: View {
    let card: JSONValue

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
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(card["label"].string ?? "Sectors").sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    Spacer()
                    Text(card["count"].string ?? "").sType(BK.small, tabular: false).foregroundStyle(S.secondary)
                }
                Text(card["writeUp"].array.compactMap(\.string).joined(separator: " "))
                    .sType(SType(size: 17, weight: 500, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                ForEach(Array(card["leadsTrails"].array.enumerated()), id: \.offset) { _, r in
                    BHairline()
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r["label"].string ?? "").sType(BK.caption, tabular: false).foregroundStyle(S.secondary)
                            Text(r["sector"].string ?? "").sType(BK.row, tabular: false).foregroundStyle(S.ink)
                        }
                        Spacer()
                        BMove(text: r["move"].string, color: r["moveColor"].string, type: SType(size: 15, weight: 700, line: 18, tracking: 0))
                        Image(systemName: "chevron.right").sFont(13, .semibold).foregroundStyle(S.secondary)
                    }
                    .padding(.vertical, 4)
                    // The row's own aria, less its "Show its map" (the row does nothing on a tap, so no button trait).
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.rowSays(r))
                }
            }
            .frame(width: 300, alignment: .leading)
            .frame(minHeight: 260, alignment: .top)
            .briefCard()
            ForEach(Array(maps.enumerated()), id: \.offset) { _, m in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m["title"].string ?? "").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            if let w = m["weightOfSP500"].string {
                                Text("\(w) of the S&P 500").sType(BK.rowSub, tabular: false).foregroundStyle(S.secondary)
                            }
                        }
                        Spacer()
                        BMove(text: m["move"].string, color: m["moveColor"].string, type: SType(size: 15, weight: 700, line: 18, tracking: 0))
                    }
                    // "Technology, 32% of the S&P 500, up 1.83%": the triangle speaks as a word (BMove).
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    BHeatMap(page: m)
                }
                .frame(width: 300, alignment: .leading)
                .frame(minHeight: 260, alignment: .top)
                .briefCard()
            }
        }
    }
}

// MARK: - Your names and the watchlist (two maps)

struct BNamesRow: View {
    let card: JSONValue
    var body: some View {
        BRow {
            ForEach(Array(card["pages"].array.enumerated()), id: \.offset) { _, p in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(p["title"].string ?? "").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        Spacer()
                        BMove(text: p["move"].string, color: p["moveColor"].string, type: SType(size: 15, weight: 700, line: 18, tracking: 0))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    BHeatMap(page: p)
                }
                .frame(width: 322, alignment: .leading)
                .briefCard()
            }
        }
    }
}
