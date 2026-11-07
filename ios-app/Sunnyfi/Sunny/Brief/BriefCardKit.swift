//
//  BriefCardKit.swift
//  Sunny
//
//  The parts every New Home card is made of (block 29, README 11): the card title (20/24 bold), its sub line
//  (13/16 medium secondary), body sentences (15/21 medium), rows split by hairlines, the white logo circle,
//  a move with its triangle, three stat columns, the segmented control, small bar charts and heat maps.
//  Colour roles come from the content ("green", "red", "orange", "ink", "secondary", "navy", "brown").
//

import SwiftUI

enum BK {
    static let title = SType(size: 20, weight: 700, line: 24, tracking: 0)
    static let sub = SType(size: 13, weight: 500, line: 16, tracking: 0)
    static let body = SType(size: 15, weight: 500, line: 21, tracking: 0)
    static let row = SType(size: 15, weight: 600, line: 20, tracking: 0)
    static let rowSub = SType(size: 12, weight: 500, line: 16, tracking: 0)
    static let small = SType(size: 13, weight: 500, line: 18, tracking: 0)
    static let caption = SType(size: 11, weight: 500, line: 13, tracking: 0)
    static let label = SType(size: 12, weight: 500, line: 15, tracking: 0)
    static let stat = SType(size: 17, weight: 800, line: 22, tracking: 0)
    static let big = SType(size: 40, weight: 800, line: 46, tracking: -0.03)

    static func color(_ c: String?) -> Color {
        switch c {
        case "green": S.green
        case "red": S.red
        case "orange": S.act
        case "secondary", "muted": S.secondary
        case "navy": S.navy
        case "brown": S.brown
        case "teal": S.teal
        default: S.ink
        }
    }
}

// MARK: - Text pieces

struct BTitle: View {
    let t: String?
    var body: some View {
        if let t { Text(t).sType(BK.title, tabular: false).foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true) }
    }
}

struct BSub: View {
    let t: String?
    var privacy = false
    var body: some View {
        if let t { Text(BriefWords.plain(t, privacy: privacy)).sType(BK.sub, tabular: false).foregroundStyle(S.secondary).fixedSize(horizontal: false, vertical: true) }
    }
}

/// A sentence that may be a plain string or rich spans.
struct BBody: View {
    let v: JSONValue
    var privacy = false
    var type = BK.body
    var body: some View {
        if !v.isNull {
            BriefWords.text(BriefSpan.list(v), base: type, privacy: privacy).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BFooter: View {
    let v: JSONValue
    var privacy = false
    var body: some View {
        if !v.isNull {
            BriefWords.text(BriefSpan.list(v), base: SType(size: 12, weight: 600, line: 15, tracking: 0), baseColor: S.secondary, privacy: privacy)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BHairline: View {
    var body: some View { Rectangle().fill(S.hairline).frame(height: 0.5) }
}

/// A move with its triangle, coloured: "▲ 0.40%" green, "▼ 0.18%" red. Content that already carries an arrow
/// (↑ ↓) is shown as is.
struct BMove: View {
    let text: String?
    let color: String?
    var signed: Double? = nil
    var type = SType(size: 15, weight: 700, line: 18, tracking: 0)
    var body: some View {
        if let t = text {
            let hasArrow = t.contains("↑") || t.contains("↓") || t.contains("▲") || t.contains("▼")
            let up = (signed ?? 0) >= 0 && color != "red"
            Text(hasArrow ? t : "\(up ? "▲" : "▼") \(t)")
                .sType(type).foregroundStyle(BK.color(color))
        }
    }
}

/// The white logo circle (36 in rows, 28 in By name, 46 in the Positions strip).
struct BLogo: View {
    let ticker: String?
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            Circle().fill(.white)
            if let t = ticker, let img = UIImage(named: "logo-\(t)") {
                Image(uiImage: img).resizable().scaledToFit().frame(width: size * 0.62, height: size * 0.62)
            } else if let t = ticker {
                Text(String(t.prefix(4))).font(.system(size: size * 0.26, weight: .bold)).foregroundStyle(Color(hex: 0x1D1D1F))
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK: - Stats

/// Three stats side by side: the value (17 heavy, coloured), the label above or the sub under (11 secondary).
struct BStats: View {
    let stats: [JSONValue]
    var privacy = false
    var labelFirst = true
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 2) {
                    if labelFirst, let l = s["label"].string { Text(l).sType(BK.label, tabular: false).foregroundStyle(S.secondary) }
                    Text(BriefWords.plain(s["value"].string, privacy: privacy))
                        .sType(SType(size: 22, weight: 800, line: 26, tracking: -0.01))
                        .foregroundStyle(BK.color(s["valueColor"].string))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let sub = s["sub"].string { Text(BriefWords.plain(sub, privacy: privacy)).sType(BK.label, tabular: false).foregroundStyle(S.secondary) }
                    if !labelFirst, let l = s["label"].string { Text(l).sType(BK.label, tabular: false).foregroundStyle(S.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Segmented control (Liquid Glass thumb, spring)

struct BSegmented: View {
    let items: [String]
    @Binding var selected: String
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { s in
                Button { withAnimation(reduce ? nil : .timingCurve(0.3, 1.4, 0.5, 1, duration: 0.45)) { selected = s } } label: {
                    Text(s).font(.system(size: 13, weight: s == selected ? .semibold : .medium))
                        .foregroundStyle(S.ink)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background {
                            if s == selected {
                                Capsule().fill(S.dynA(0xFFFFFF, 0.88, 0xFFFFFF, 0.20))
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(s == selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(S.dynA(0x767680, 0.12, 0x767680, 0.24)))
    }
}

// MARK: - Bars

/// A row of value bars with labels under them; the highlighted one is full green, the rest pale green.
struct BBars: View {
    let bars: [JSONValue]
    var height: CGFloat = 70
    var privacy = false
    var body: some View {
        let vals = bars.map { $0["value"].double ?? 0 }
        let mx = max(vals.max() ?? 1, 0.0001)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(bars.enumerated()), id: \.offset) { i, b in
                let hl = b["highlight"].bool
                VStack(spacing: 4) {
                    Text(BriefWords.plain(b["value"].string, privacy: privacy))
                        .sType(SType(size: 11, weight: 700, line: 13, tracking: 0))
                        .foregroundStyle(hl ? S.green : BK.color(b["valueColor"].string))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(b["empty"].bool ? S.chip : hl ? S.green : S.green.opacity(0.3))
                        .frame(height: max(4, height * CGFloat(vals[i] / mx)))
                    Text(b["label"].string ?? "").sType(SType(size: 11, weight: hl ? 700 : 500, line: 13, tracking: 0))
                        .foregroundStyle(hl ? S.ink : S.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Heat map

/// A heat map drawn from the content's own tiles (rects on a 305 × 196 grid, colours by move).
struct BHeatMap: View {
    let page: JSONValue
    @Environment(BriefState.self) private var brief
    var body: some View {
        let size = page["mapSize"].array.compactMap(\.double)
        let mw = size.first ?? 305, mh = size.count > 1 ? size[1] : 196
        GeometryReader { g in
            let sx = g.size.width / mw, sy = g.size.height / mh
            ZStack(alignment: .topLeading) {
                ForEach(Array(page["tiles"].array.enumerated()), id: \.offset) { _, t in
                    let r = t["rect"].array.compactMap(\.double)
                    if r.count == 4 {
                        let w = r[2] * sx, h = r[3] * sy
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Self.fill(t))
                            VStack(spacing: 1) {
                                Text(t["ticker"].string ?? t["name"].string ?? "")
                                    .font(.system(size: w < 50 || h < 40 ? 10 : 13, weight: .bold))
                                if t["showsMove"].bool, let m = t["moveText"].string {
                                    Text("\((t["move"].double ?? 0) >= 0 ? "▲" : "▼")\(m)")
                                        .font(.system(size: w < 50 || h < 40 ? 9 : 12, weight: .medium).monospacedDigit())
                                }
                            }
                            .foregroundStyle(Color(hex: 0x1D1D1F))
                            .minimumScaleFactor(0.6)
                            .padding(2)
                        }
                        .frame(width: w, height: h)
                        .contentShape(Rectangle())
                        // The ticker chart is the sample's until its real series lands (Pass 2); real tiles do not open it yet.
                        .onTapGesture { if BriefDebug.sample, let t = t["ticker"].string, SampleBook.q[t] != nil { brief.ticker = t } }
                        .offset(x: r[0] * sx, y: r[1] * sy)
                    }
                }
            }
        }
        .aspectRatio(mw / mh, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(page["aria"].string ?? "")
    }

    static func fill(_ t: JSONValue) -> Color {
        if let hex = t["bg"].string?.replacingOccurrences(of: "#", with: ""), let v = UInt32(hex, radix: 16) { return Color(hex: v) }
        return S.chip
    }
}

/// Cards in a sideways row: the first full width less a peek of the next (block 29 rows).
struct BRow<Content: View>: View {
    var width: CGFloat? = nil
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) { content() }
                .scrollTargetLayout()
                .padding(.horizontal, S.margin)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}
