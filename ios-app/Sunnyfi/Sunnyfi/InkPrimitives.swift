//
//  InkPrimitives.swift
//  Sunnyfi — Ink design system (greenfield rebuild)
//
//  The eleven product primitives every screen composes from. Faithful port of the
//  Ink handoff: fixed-size cards, the seven card zones, the three foot patterns
//  (Bars / Band3 / ledger), the freshness Stamp, and the signed Delta.
//
//  Law 1 — hue only on data (loss/gain/delayed); chrome is monochrome; selection
//  is inversion. Law 2 — opacity is relevance. Numbers are mono; prose Inter;
//  headings Newsreader.
//

import SwiftUI

// MARK: - Formatting (display only)

/// Compact USD, matching the prototype `usd()`: $X.XXM for millions, else $rounded.
func inkUsd(_ n: Double) -> String {
    let a = abs(n)
    if a >= 1_000_000 {
        let m = n / 1_000_000
        return "$" + String(format: a >= 10_000_000 ? "%.1f" : "%.2f", m)
            .replacingOccurrences(of: #"\.0+$"#, with: "", options: .regularExpression) + "M"
    }
    return "$" + Int(n.rounded()).formatted(.number.grouping(.automatic))
}

// MARK: - Small shapes / modifiers

private struct InkVLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: 1, y: 0)); p.addLine(to: CGPoint(x: 1, y: r.height)); return p
    }
}

/// Live-dot pulse: opacity 1 → .35, scale 1 → .7, forever.
private struct InkPulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.35 : 1).scaleEffect(on ? 0.7 : 1)
            .animation(.easeInOut(duration: InkMotion.pulse).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// Numbers in prose go mono at full ink; the surrounding prose is Inter-light dim
/// (the Ink `Fig` treatment). Returns a concatenated Text.
func inkFig(_ s: String) -> Text {
    let pattern = try! NSRegularExpression(pattern: #"\$?\d[\d,.–−\-]*%?(?:\s(?:ct|sh|pts))?"#)
    let ns = s as NSString
    var out = Text("")
    var last = 0
    for m in pattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
        if m.range.location > last {
            out = out + Text(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
                .font(InkFont.display(12.5, .light)).foregroundStyle(Ink.dim)
        }
        out = out + Text(ns.substring(with: m.range)).font(InkFont.mono(12.5)).foregroundStyle(Ink.text)
        last = m.range.location + m.range.length
    }
    if last < ns.length {
        out = out + Text(ns.substring(from: last)).font(InkFont.display(12.5, .light)).foregroundStyle(Ink.dim)
    }
    return out
}

// MARK: - 11 · Delta (a signed figure + its arrow)

struct InkDelta: View {
    var value: String
    var good: Bool?                 // nil = flat → renders `·`
    var size: CGFloat = 17
    var weight: Font.Weight = .regular
    var body: some View {
        HStack(spacing: size > 24 ? 9 : 6) {
            Text(value).font(InkFont.mono(size, weight))
            Text(good == nil ? "·" : (good! ? "↑" : "↓")).font(InkFont.mono(size * 0.82))
        }
        .foregroundStyle(Ink.signed(good))
    }
}

// MARK: - 1 · Card

struct InkCard<Content: View>: View {
    enum Spine { case short, long }   // solid text = sold/short · dashed dim = bought/long
    var relevance: InkRelevance = .r1
    var spine: Spine? = nil
    var compact: Bool = false
    var height: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .leading) {
            Ink.surface
            spineView
            VStack(spacing: 0) { content }
        }
        .frame(width: compact ? 306 : 348, height: height ?? (compact ? 374 : 530), alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).strokeBorder(Ink.hair, lineWidth: 1))
        .inkRelevance(relevance)
    }

    @ViewBuilder private var spineView: some View {
        switch spine {
        case .short: InkVLine().stroke(Ink.text, lineWidth: 2).frame(width: 2)
        case .long:  InkVLine().stroke(Ink.dim, style: .init(lineWidth: 2, dash: [3, 3])).frame(width: 2)
        case nil:    EmptyView()
        }
    }
}

// MARK: - 2 · Body  (flex:1 — the caller drops a Spacer to pin the band to the bottom)

struct InkBody<Content: View>: View {
    var compact: Bool = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(EdgeInsets(top: compact ? 20 : 22, leading: compact ? 18 : 22,
                                bottom: compact ? 22 : 24, trailing: compact ? 18 : 22))
    }
}

/// The flex:1 spacer that aligns bands across cards of equal height.
struct InkSpacer: View { var body: some View { Spacer(minLength: 0) } }

// MARK: - 3 · Eyebrow

struct InkEyebrow<Right: View>: View {
    var n: String? = nil
    var cat: String
    var glyph: String? = nil
    @ViewBuilder var right: Right

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                if let glyph { Text(glyph).font(.system(size: 12)).foregroundStyle(Ink.text) }
                Text(([n, cat].compactMap { $0 }.joined(separator: " · ")).uppercased())
                    .font(InkFont.mono(9.5)).tracking(9.5 * 0.18).foregroundStyle(Ink.dim)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
            right
        }
        .frame(minHeight: 24)
    }
}

extension InkEyebrow where Right == EmptyView {
    init(n: String? = nil, cat: String, glyph: String? = nil) {
        self.init(n: n, cat: cat, glyph: glyph) { EmptyView() }
    }
}

// MARK: - 4 · Hero  (one loudest number per card)

struct InkHero: View {
    var value: String
    var unit: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(InkFont.mono(44, .light)).tracking(44 * -0.04).foregroundStyle(Ink.text)
            if let unit {
                Text(unit.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.16)
                    .foregroundStyle(Ink.dim).padding(.top, 12)
            }
        }
        .padding(.top, 24)
    }
}

// MARK: - 5 · Band  (status chip — Law-1 severity order: low → mod → hued)

struct InkBand: View {
    enum Skin { case low, mod, hue(Color) }
    var skin: Skin
    var text: String

    var body: some View {
        Text(text.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.14)
            .foregroundStyle(fg)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(bg))
            .overlay { if case .mod = skin { Capsule().strokeBorder(Ink.dim, lineWidth: 1) } }
            .fixedSize()
    }
    private var fg: Color {
        switch skin { case .low: return Ink.dim; case .mod: return Ink.text; case .hue(let h): return h }
    }
    private var bg: Color {
        switch skin { case .low: return Ink.text.opacity(0.08); case .mod: return .clear; case .hue(let h): return h.opacity(0.16) }
    }
}

// MARK: - 6 · Band3  (2–3 metric columns above the foot)

struct InkBand3: View {
    let items: [(k: String, v: String)]
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 0) {
                    Text(items[i].k.uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.14)
                        .foregroundStyle(Ink.dim).lineLimit(1)
                    Text(items[i].v).font(InkFont.mono(17)).tracking(17 * -0.02)
                        .foregroundStyle(Ink.text).padding(.top, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, i == 0 ? 0 : 12).padding(.trailing, 12)
                .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Ink.hair).frame(width: 1) } }
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }
}

// MARK: - 7 · Bullets  (≤2 lines; numbers in prose go mono)

struct InkBullets: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(items, id: \.self) { t in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Circle().fill(Ink.dim).frame(width: 4, height: 4).offset(y: -3)
                    inkFig(t).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 18)
    }
}

// MARK: - 8 · Foot  (bottom zone — transparent, defined by its hairline)

struct InkFoot<Content: View>: View {
    var compact: Bool = false
    var flat: Bool = false
    var height: CGFloat? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height ?? (compact ? 96 : 132))
            .padding(.horizontal, compact ? 18 : 22)
            .overlay(alignment: .top) { if !flat { Rectangle().fill(Ink.hair).frame(height: 1) } }
    }
}

// MARK: - 9 · Stamp  (data freshness — the last 30px strip)

struct InkStamp: View {
    enum FreshState { case live, delayed, stale }
    var state: FreshState
    var text: String
    var compact: Bool = false
    var flat: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            dot
            Text(text.uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.1)
                .foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.tail)
        }
        .frame(height: 30).frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 18 : 22)
        .overlay(alignment: .top) { if !flat { Rectangle().fill(Ink.hair).frame(height: 1) } }
    }

    @ViewBuilder private var dot: some View {
        switch state {
        case .live:    Circle().fill(Ink.loss).frame(width: 6, height: 6).modifier(InkPulse())
        case .delayed: Circle().fill(Ink.delayed).frame(width: 6, height: 6)
        case .stale:   Circle().strokeBorder(Ink.dim, lineWidth: 1.5).frame(width: 6, height: 6)
        }
    }
}

// MARK: - 10 · Bars  (1–3 horizontal comparison bars; reference dim, compared hued)

struct InkBars<Net: View>: View {
    var leftK: String
    var leftV: Double
    var rightK: String
    var rightV: Double
    var hue: Color
    @ViewBuilder var net: Net
    @State private var grow = false

    var body: some View {
        let maxV = max(leftV, rightV, 1)
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(leftK) vs \(rightK)".uppercased()).font(InkFont.mono(9)).tracking(9 * 0.16)
                    .foregroundStyle(Ink.dim)
                Spacer(minLength: 0)
                net
            }
            barLine(leftK, leftV, strong: true, maxV: maxV)
            barLine(rightK, rightV, strong: false, maxV: maxV)
        }
        .onAppear { withAnimation(InkMotion.ease(0.9).delay(0.14)) { grow = true } }
    }

    private func barLine(_ k: String, _ v: Double, strong: Bool, maxV: Double) -> some View {
        HStack(spacing: 10) {
            Text(k.uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.1)
                .foregroundStyle(Ink.dim).frame(width: 62, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.hair)
                    Capsule().fill(strong ? Ink.dim : hue)
                        .frame(width: max(0, CGFloat(v / maxV) * g.size.width * (grow ? 1 : 0)))
                }
            }
            .frame(height: 7)
            Text(inkUsd(v)).font(InkFont.mono(12)).foregroundStyle(strong ? Ink.text : hue)
                .frame(minWidth: 74, alignment: .trailing).lineLimit(1)
        }
    }
}
