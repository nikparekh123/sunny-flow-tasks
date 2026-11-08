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
    static let cardSub = SType(size: 15, weight: 500, line: 20, tracking: 0)   // the design's card sub line, under the title
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

// MARK: - Spoken words (VoiceOver, Pass 5)

/// What VoiceOver says for a figure or a line: BriefWords.speech (the mask speaks "hidden", arrows "up" and
/// "down", "$6.2K" "6.2 thousand dollars", "%" "percent", " · " a pause), plus the card glyphs it leaves:
/// "×71" speaks "71 contracts", "3.9×" speaks "3.9 times", "→" "to", and "●" "›" "↗" "↘" are silent.
/// The words themselves stay the server's.
enum BSay {
    static func words(_ s: String?, privacy: Bool = false) -> String {
        guard let s, !s.isEmpty else { return "" }
        var t = BriefWords.speech(BriefWords.plain(s, privacy: privacy))
        for (g, w) in [("→", " to "), ("↗", " "), ("↘", " "), ("●", " "), ("›", " ")] {
            t = t.replacingOccurrences(of: g, with: w)
        }
        t = t.replacingOccurrences(of: #"\s*×(\d+(?:,\d{3})*)"#, with: ", $1 contracts", options: .regularExpression)
        t = t.replacingOccurrences(of: "×", with: " times")
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Rich spans as one spoken line.
    static func spans(_ v: JSONValue, privacy: Bool = false) -> String {
        words(BriefSpan.list(v).map(\.t).joined(), privacy: privacy)
    }

    /// A move as the screen colours it: "0.40%" in green speaks "up 0.40%", in red "down 0.40%".
    static func move(_ text: String?, color: String?, signed: Double? = nil) -> String {
        guard let t = text, !t.isEmpty else { return "" }
        if t.contains(where: { "↑↓▲▼".contains($0) }) { return words(t) }
        let up = (signed ?? 0) >= 0 && color != "red"
        return words("\(up ? "up" : "down") \(t)")
    }

    /// A book figure whose red carries the loss (shown without a minus sign): "down" in front, never "minus".
    static func figure(_ s: String?, color: String?, privacy: Bool) -> String {
        let w = words(s, privacy: privacy)
        guard color == "red", !w.isEmpty, !w.hasPrefix("down"), !w.hasPrefix("up") else { return w }
        return "down " + w
    }

    /// Items joined for one spoken label, the empty ones left out.
    static func join(_ parts: [String?], _ sep: String = ", ") -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: sep)
    }
}

// MARK: - Text pieces

extension View {
    /// One line of text in a box exactly its CSS line height. sType's box lands a fraction taller (the font's own
    /// line rounds to the pixel), which adds up down a long list (Overnight's nine rows ran 3 pt long). At a larger
    /// text size the line is free to wrap, as before.
    func bLine(_ t: SType, tabular: Bool = true) -> some View { modifier(BLineModifier(t: t, tabular: tabular)) }
}

private struct BLineModifier: ViewModifier {
    let t: SType
    let tabular: Bool
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales
    func body(content: Content) -> some View {
        if scales && t.scaled(dts).size != t.size {
            content.sType(t, tabular: tabular).fixedSize(horizontal: false, vertical: true)
        } else {
            content.sType(t, tabular: tabular).lineLimit(1).frame(height: t.line)
        }
    }
}

struct BTitle: View {
    let t: String?
    var body: some View {
        if let t { Text(t).sType(BK.title, tabular: false).foregroundStyle(S.ink).fixedSize(horizontal: false, vertical: true) }
    }
}

struct BSub: View {
    let t: String?
    var privacy = false
    /// 13/16 for a sub beside a title (the overnight list); a card's own sub line under its title is 15/20 (`BK.cardSub`).
    var type = BK.sub
    var body: some View {
        if let t {
            BriefWords.line(t, privacy: privacy)
                .sType(type, tabular: false).foregroundStyle(S.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A sentence that may be a plain string or rich spans.
struct BBody: View {
    let v: JSONValue
    var privacy = false
    var type = BK.body
    var body: some View {
        if !v.isNull {
            BriefSentence(BriefSpan.list(v), base: type, privacy: privacy).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BFooter: View {
    let v: JSONValue
    var privacy = false
    var type = SType(size: 12, weight: 600, line: 15, tracking: 0)
    var body: some View {
        if !v.isNull {
            BriefSentence(BriefSpan.list(v), base: type, baseColor: S.secondary, privacy: privacy)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The rule between rows: the design's `border-top: 1px solid var(--line)`.
struct BHairline: View {
    var body: some View { Rectangle().fill(S.hairline).frame(height: 1) }
}

/// The design's CSS triangle (borders on a zero box): point up, or turned 180° for down.
struct BTriangle: Shape {
    var up = true
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// A move with its triangle, coloured: "▲ 0.40%" green, "▼ 0.18%" red. Content that already carries an arrow
/// (↑ ↓) is shown as is. The triangle is the design's: 10 × 7.5, 4 before the figure, unless a card says otherwise.
struct BMove: View {
    let text: String?
    let color: String?
    var signed: Double? = nil
    var type = SType(size: 15, weight: 700, line: 18, tracking: 0)
    var tri = CGSize(width: 10, height: 7.5)
    var gap: CGFloat = 4
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales
    var body: some View {
        if let t = text {
            let hasArrow = t.contains("↑") || t.contains("↓") || t.contains("▲") || t.contains("▼")
            let up = (signed ?? 0) >= 0 && color != "red"
            // The triangle grows with the text when the screen follows the phone's text size.
            let k = scales ? SDynamic.scaled(type.size, dts) / type.size : 1
            Group {
                if hasArrow {
                    Text(t).bLine(type)
                } else {
                    HStack(spacing: gap * k) {
                        BTriangle(up: up).frame(width: tri.width * k, height: tri.height * k)
                        Text(t).bLine(type)
                    }
                }
            }
            .foregroundStyle(BK.color(color))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BSay.move(t, color: color, signed: signed))
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
                Image(uiImage: img).resizable().scaledToFit().frame(width: size * 0.74, height: size * 0.74)   // design: center/74%
            } else if let t = ticker {
                Text(String(t.prefix(4))).font(.system(size: size * 0.26, weight: .bold)).foregroundStyle(Color(hex: 0x1D1D1F))
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5).padding(-0.25))   // box-shadow 0 0 0 .5px, outside
        .accessibilityHidden(true)
    }
}

// MARK: - Stats

/// Three stats side by side: the value (heavy, coloured), the label above or the sub under (12/15 secondary).
/// The design's Results grid: 12 apart, 1 between lines, 22/27. Earnings ahead and Thesis check: 10 apart, 20/25.
struct BStats: View {
    let stats: [JSONValue]
    var privacy = false
    var labelFirst = true
    var value = SType(size: 22, weight: 800, line: 27, tracking: -0.02)
    var spacing: CGFloat = 12
    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 1) {
                    if labelFirst, let l = s["label"].string { Text(l).sType(BK.label, tabular: false).foregroundStyle(S.secondary) }
                    BriefWords.line(s["value"].string, privacy: privacy)
                        .sType(value)
                        .foregroundStyle(BK.color(s["valueColor"].string))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let sub = s["sub"].string { BriefWords.line(sub, privacy: privacy).sType(BK.label, tabular: false).foregroundStyle(S.secondary) }
                    if !labelFirst, let l = s["label"].string { Text(l).sType(BK.label, tabular: false).foregroundStyle(S.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // One stop per stat: "Long, down $14,560, unrealized" (or "down hidden" under privacy).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BSay.join([s["label"].string, BSay.figure(s["value"].string, color: s["valueColor"].string, privacy: privacy),
                                               BSay.words(s["sub"].string, privacy: privacy)]))
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
        let at = items.firstIndex(of: selected), n = CGFloat(max(1, items.count))
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { s in
                // The card under the control reflows on the page curve (bars fill on it too); only the thumb springs.
                Button { withAnimation(S.moving(S.page, reduce)) { selected = s } } label: {
                    Text(s).sFont(13, s == selected ? .semibold : .medium)
                        .foregroundStyle(S.ink)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(s == selected ? .isSelected : [])
            }
        }
        .background(alignment: .leading) {
            // One thumb that slides between the segments (S.spring, 0.45 s), instant under Reduce Motion.
            GeometryReader { g in
                Capsule().fill(S.dynA(0xFFFFFF, 0.88, 0xFFFFFF, 0.20))
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                    .frame(width: g.size.width / n)
                    .offset(x: g.size.width / n * CGFloat(at ?? 0))
                    .opacity(at == nil ? 0 : 1)
                    .animation(S.moving(S.spring, reduce), value: selected)
            }
        }
        .padding(2)
        .background(Capsule().fill(S.dynA(0x767680, 0.12, 0x767680, 0.24)))
        .sensoryFeedback(.selection, trigger: selected)
    }
}

// MARK: - Bars

/// A row of value bars with labels under them, 10 apart; the highlighted one is full green, the rest green at 35%.
struct BBars: View {
    let bars: [JSONValue]
    @Environment(\.dynamicTypeSize) private var dts
    var height: CGFloat = 70
    var privacy = false
    /// The chart's title, the start of its spoken summary ("Yield, week by week: Sep 28 0.48%, ...").
    var title: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// One spoken line for the whole chart: each bar's label and value, a loss as "down", money "hidden" under privacy.
    private func summary(_ vals: [Double]) -> String {
        let items = bars.enumerated().map { i, b -> String in
            let v = BSay.words(b["value"].string, privacy: privacy)
            return BSay.join([b["label"].string, v.isEmpty ? (b["empty"].bool ? "none yet" : nil) : (vals[i] < 0 ? "down " + v : v)], " ")
        }
        return BSay.join([title, items.joined(separator: ", ")], ": ")
    }

    var body: some View {
        // The signed number when the server sends one (`n` money, `signed` a yield): a month or week that lost draws
        // red, its label without a minus sign. Else the label's own number.
        let vals = bars.map { $0["n"].double ?? $0["signed"].double ?? $0["value"].double ?? 0 }
        let mx = max(vals.map(abs).max() ?? 1, 0.0001)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(bars.enumerated()), id: \.offset) { i, b in
                let hl = b["highlight"].bool, neg = vals[i] < 0, tint = neg ? S.red : S.green
                VStack(spacing: 4) {
                    BriefWords.line(b["value"].string, privacy: privacy)
                        .sType(SType(size: 11, weight: hl ? 800 : 700, line: 14, tracking: 0))
                        .foregroundStyle(hl ? tint : BK.color(b["valueColor"].string))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(b["empty"].bool ? S.chip : hl ? tint : tint.opacity(0.35))
                        .frame(height: max(4, height * CGFloat(abs(vals[i]) / mx)))
                        // Bar fills on the page curve (never the segmented spring), instant under Reduce Motion.
                        .animation(S.moving(S.page, reduce), value: vals[i])
                    Text(b["label"].string ?? "").sType(SType(size: 11, weight: hl ? 800 : 500, line: 14, tracking: 0))
                        .foregroundStyle(hl ? S.ink : S.secondary)
                        // One line (a touch smaller if needed) as designed; at large text it wraps, never "This..." (Audit 6).
                        .lineLimit(dts > .large ? nil : 1).minimumScaleFactor(dts > .large ? 1 : 0.8)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: dts > .large)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(vals))
    }
}

// MARK: - Heat map

/// A heat map drawn from the content's own tiles (rects on a 305 × 196 grid, colours by move).
struct BHeatMap: View {
    let page: JSONValue
    @Environment(BriefState.self) private var brief

    /// The design's type steps for a tile (SunnyEconomy mapCard): ticker and move 15/14, 13/12 or 12/11 when both fit,
    /// else the ticker alone, else nothing. `w`, `h` are the tile's own size. The design's alone step is 10, but its
    /// layout never leaves a tile that small (it grows the floor first); the server's can, so 11, the README's least.
    static func tier(_ ticker: String, _ w: CGFloat, _ h: CGFloat) -> (tf: CGFloat, pf: CGFloat) {
        let n = CGFloat(ticker.count)
        func tw(_ f: CGFloat) -> CGFloat { n * f * 0.66 + 8 }
        func pw(_ f: CGFloat) -> CGFloat { 5 * f * 0.6 + 8 + f * 0.6 + 3 }
        if w >= tw(15), w >= pw(14), h >= 52 { return (15, 14) }
        if w >= tw(13), w >= pw(12), h >= 40 { return (13, 12) }
        if w >= tw(12), w >= pw(11), h >= 34 { return (12, 11) }
        if w >= tw(11), h >= 16 { return (11, 0) }
        return (0, 0)
    }

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
                        let tk = t["ticker"].string ?? t["name"].string ?? ""
                        let f = Self.tier(tk, w, h)
                        ZStack {
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Self.fill(t))
                            if f.tf > 0 {
                                // Centred column, 3 apart, each line 1.1 of its size; the move's triangle as the design draws it.
                                VStack(spacing: 3) {
                                    Text(tk).sType(SType(size: f.tf, weight: 700, line: f.tf * 1.1, tracking: 0), tabular: false)
                                    if f.pf > 0, t["showsMove"].bool, let m = t["moveText"].string {
                                        let tw = (f.pf * 0.6).rounded() / 2, th = (f.pf * 0.9).rounded() / 2
                                        HStack(spacing: f.pf >= 13 ? 3 : 2) {
                                            BTriangle(up: (t["move"].double ?? 0) >= 0).frame(width: tw * 2, height: th)
                                            Text(m).sType(SType(size: f.pf, weight: 500, line: f.pf * 1.1, tracking: 0))
                                        }
                                    }
                                }
                                .foregroundStyle(S.ink)
                                .lineLimit(1)   // never wrap the % onto its own line (FIS ▼26.04%): shrink a little first
                                .minimumScaleFactor(0.8)
                                .padding(2)
                            }
                        }
                        .frame(width: w, height: h)
                        .contentShape(Rectangle())
                        // The ticker chart is the sample's until its real series lands (Pass 2); real tiles do not open it yet.
                        .onTapGesture { if let t = t["ticker"].string, Self.opens(t) { brief.ticker = t } }
                        .offset(x: r[0] * sx, y: r[1] * sy)
                    }
                }
            }
        }
        .aspectRatio(mw / mh, contentMode: .fit)
        .environment(\.sTypeScales, false)   // tiles keep their size: their boxes are drawn to it
        // One stop with the map's summary; each tile's tap is an action ("Open Nike chart") in the Actions rotor.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSay.words(page["aria"].string))
        .accessibilityActions {
            ForEach(Array(page["tiles"].array.enumerated()), id: \.offset) { _, t in
                if let tk = t["ticker"].string, Self.opens(tk) {
                    Button("Open \(t["name"].string ?? tk) chart") { brief.ticker = tk }
                }
            }
        }
    }

    private static func opens(_ t: String) -> Bool { !BriefDebug.sample || SampleBook.q[t] != nil }

    static func fill(_ t: JSONValue) -> Color {
        // The move picks the step in both themes; the server's light hex is only a fallback.
        if let m = t["move"].double { return S.heatTile(m) }
        if let hex = t["bg"].string?.replacingOccurrences(of: "#", with: ""), let v = UInt32(hex, radix: 16) { return Color(hex: v) }
        return S.chip
    }
}

/// Cards in a sideways row: the first full width less a peek of the next (block 29 rows).
struct BRow<Content: View>: View {
    var width: CGFloat? = nil
    /// 12 between cards; the index cards sit 8 apart.
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: spacing) { content() }
                .scrollTargetLayout()
                .padding(.horizontal, S.margin)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}
