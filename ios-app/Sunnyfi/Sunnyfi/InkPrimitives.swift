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

/// Compact USD: $1.85M for millions, $100K / $12.3K for thousands, else grouped.
func inkUsd(_ n: Double) -> String {
    let a = abs(n), sign = n < 0 ? "−" : ""
    func trim(_ s: String) -> String { s.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) }
    if a >= 1_000_000 { return sign + "$" + trim(String(format: a >= 10_000_000 ? "%.1f" : "%.2f", a / 1_000_000)) + "M" }
    if a >= 1_000 { return sign + "$" + trim(String(format: a >= 100_000 ? "%.0f" : "%.1f", a / 1_000)) + "K" }
    return sign + "$" + Int(a.rounded()).formatted(.number.grouping(.automatic))
}

// MARK: - Small shapes / modifiers

private struct InkVLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: 1, y: 0)); p.addLine(to: CGPoint(x: 1, y: r.height)); return p
    }
}

/// Live-dot pulse: opacity 1 → .35, scale 1 → .7, forever.
struct InkPulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.35 : 1).scaleEffect(on ? 0.7 : 1)
            .animation(.easeInOut(duration: InkMotion.pulse).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
extension View { func inkPulse() -> some View { modifier(InkPulse()) } }

// MARK: - Count-up (the prototype `Roll`: prices roll from 96%, integers from 0)

/// Interpolate every numeric token in a string toward its target by `t` (0…1).
func inkRolled(_ s: String, _ t: Double) -> String {
    if t >= 1 { return s }
    let pattern = try! NSRegularExpression(pattern: #"\d[\d,]*(?:\.\d+)?"#)
    let ns = s as NSString
    var out = ""; var last = 0
    for m in pattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
        if m.range.location > last { out += ns.substring(with: NSRange(location: last, length: m.range.location - last)) }
        let raw = ns.substring(with: m.range)
        let grouped = raw.contains(",")
        let dec: Int = raw.firstIndex(of: ".").map { raw.distance(from: raw.index(after: $0), to: raw.endIndex) } ?? 0
        let target = Double(raw.replacingOccurrences(of: ",", with: "")) ?? 0
        let from = (dec == 2 && target >= 50) ? target * 0.96 : 0
        let v = from + (target - from) * t
        out += grouped
            ? v.formatted(.number.precision(.fractionLength(dec)).grouping(.automatic))
            : String(format: "%.\(dec)f", v)
        last = m.range.location + m.range.length
    }
    if last < ns.length { out += ns.substring(from: last) }
    return out
}

private struct InkRollMod: AnimatableModifier {
    var t: Double
    let text: String; let font: Font; let tracking: CGFloat; let color: Color
    var animatableData: Double { get { t } set { t = newValue } }
    func body(content: Content) -> some View {
        Text(inkRolled(text, t)).font(font).tracking(tracking).foregroundStyle(color)
    }
}

/// A number (inside any string) that counts up on mount. Respects reduced motion.
struct InkRoll: View {
    let text: String
    var font: Font = InkFont.mono(44, .light)
    var tracking: CGFloat = 0
    var color: Color = Ink.text
    var delay: Double = 0
    @State private var t: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Text("").modifier(InkRollMod(t: reduce ? 1 : t, text: text, font: font, tracking: tracking, color: color))
            .onAppear {
                guard !reduce else { return }
                t = 0
                withAnimation(.easeOut(duration: InkMotion.countUp).delay(delay)) { t = 1 }
            }
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

// MARK: - Gauge (Ink radial: 9px arc, hair track, score centred in mono)

private struct InkArc: Shape {
    var frac: Double
    var inset: CGFloat = 0
    var animatableData: Double { get { frac } set { frac = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.maxY - 4)
        let radius = max(1, min(r.width / 2, r.height) - 6 - inset)
        p.addArc(center: c, radius: radius, startAngle: .degrees(180),
                 endAngle: .degrees(180 + 180 * max(0, min(1, frac))), clockwise: false)
        return p
    }
}

/// Semicircular gauge — the value arc grows from the left over `InkMotion.countUp`.
/// `previous` draws a thinner, dimmer inner arc showing the prior close.
struct InkGauge: View {
    var value: Double          // within `range`
    var suffix: String = ""
    var previous: Double? = nil
    // Ranged / decimal / hued variant (seller score, etc). Defaults keep the
    // original 0…100 integer-percent gauge unchanged. `building` (or a value
    // below the range floor) renders a dim "—".
    var range: ClosedRange<Double> = 0...100
    var decimals: Int = 0
    var tint: Color = Ink.text
    @State private var t: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        let lo = range.lowerBound, hi = range.upperBound
        let building = value < lo
        let v = building ? lo : lo + (value - lo) * (reduce ? 1 : t)
        let frac = max(0.0001, min(1, (v - lo) / (hi - lo)))
        let center = decimals > 0 ? String(format: "%.\(decimals)f", v) : "\(Int(v.rounded()))\(suffix)"
        ZStack(alignment: .bottom) {
            InkArc(frac: 1).stroke(Ink.hair, style: .init(lineWidth: 9, lineCap: .round))
            if let prev = previous, prev >= 0 {
                InkArc(frac: 1, inset: 12).stroke(Ink.hair.opacity(0.6), style: .init(lineWidth: 4, lineCap: .round))
                InkArc(frac: max(0.0001, prev / 100), inset: 12)
                    .stroke(Ink.text.opacity(0.42), style: .init(lineWidth: 4, lineCap: .round))
            }
            if !building {
                InkArc(frac: frac).stroke(tint, style: .init(lineWidth: 9, lineCap: .round))
            }
            Text(building ? "—" : center)
                .font(InkFont.mono(34, .medium)).tracking(34 * -0.03)
                .foregroundStyle(building ? Ink.dim : Ink.text)
                .padding(.bottom, 2)
        }
        .frame(width: 150, height: 82)
        .onAppear { guard !reduce else { return }; withAnimation(.easeOut(duration: InkMotion.countUp).delay(0.12)) { t = 1 } }
    }
}

// MARK: - 11 · Delta (a signed figure + its arrow)

struct InkDelta: View {
    var value: String
    var good: Bool?                 // nil = flat (dim), else gain/loss colour — no arrow
    var size: CGFloat = 17
    var weight: Font.Weight = .regular
    // Colour alone carries P&L direction; arrows are intentionally omitted so every
    // hero number reads the same way (white = value, green/red = P&L).
    var body: some View {
        InkRoll(text: value, font: InkFont.mono(size, weight), color: Ink.signed(good))
    }
}

// MARK: - 1 · Card

struct InkCard<Content: View>: View {
    enum Spine { case short, long }   // solid text = sold/short · dashed dim = bought/long
    /// When a sleeve/shares card pulls out a paired panel, the two square their
    /// inner corners and share a 1px seam so the pair reads as one long card.
    enum Join { case start, end, middle }
    var relevance: InkRelevance = .r1
    var spine: Spine? = nil
    var compact: Bool = false
    var height: CGFloat? = nil
    var join: Join? = nil
    /// Freshness line, rendered as a caption BELOW the card surface (not inside it).
    var stamp: (state: InkStamp.FreshState, text: String)? = nil
    @ViewBuilder var content: Content

    private var w: CGFloat { compact ? 306 : 348 }
    private var corners: RectangleCornerRadii {
        let r = Ink.radiusCard
        switch join {
        case .start:  return .init(topLeading: r, bottomLeading: r, bottomTrailing: 0, topTrailing: 0)
        case .end:    return .init(topLeading: 0, bottomLeading: 0, bottomTrailing: r, topTrailing: r)
        case .middle: return .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0)
        case nil:     return .init(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            surface
            if let stamp {
                InkStamp(state: stamp.state, text: stamp.text, compact: compact, flat: true)
                    .frame(width: w, alignment: .leading)
            }
        }
        .frame(width: w, alignment: .leading)
        .inkRelevance(relevance)
    }

    private var surface: some View {
        ZStack(alignment: .leading) {
            Ink.surface
            spineView
            VStack(spacing: 0) { content }
        }
        .frame(width: w, height: height ?? (compact ? 374 : 530), alignment: .top)
        .clipShape(UnevenRoundedRectangle(cornerRadii: corners, style: .continuous))
        .overlay(UnevenRoundedRectangle(cornerRadii: corners, style: .continuous).strokeBorder(Ink.hair, lineWidth: 1))
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
            InkRoll(text: value, font: InkFont.mono(40, .bold), tracking: 40 * -0.04, color: Ink.text)
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
                    InkRoll(text: items[i].v, font: InkFont.mono(17, .medium), tracking: 17 * -0.02, color: Ink.text, delay: 0.12)
                        .padding(.top, 10)
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
        // The foot HUGS its content with a fixed vertical pad, so the stamp is
        // ALWAYS the same distance below the foot content on every card — no more
        // varying gaps from a fixed-height zone centring content differently.
        // (The flex Body absorbs the height difference.) `height` is kept for
        // source compatibility but no longer forces a fixed zone.
        let vpad: CGFloat = compact ? 14 : 18
        return VStack(alignment: .leading, spacing: compact ? 10 : 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, vpad)
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
    // Bright briefly on a fresh render, then settles to a minimally-visible grey.
    @State private var settled = false

    var body: some View {
        HStack(spacing: 8) {
            dot
            Text(text.uppercased()).font(InkFont.mono(8.5)).tracking(8.5 * 0.1)
                .foregroundStyle(Ink.text.opacity(settled ? 0.4 : 0.72)).lineLimit(1).truncationMode(.tail)
        }
        .frame(height: 30).frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 18 : 22)
        .overlay(alignment: .top) { if !flat { Rectangle().fill(Ink.hair).frame(height: 1) } }
        .onAppear { settled = false; withAnimation(.easeInOut(duration: 2.5).delay(6)) { settled = true } }
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
            InkRoll(text: inkUsd(v), font: InkFont.mono(12, .medium), color: strong ? Ink.text : hue, delay: 0.14)
                .frame(minWidth: 74, alignment: .trailing).lineLimit(1)
        }
    }
}
