//
//  IncParts.swift
//  Sunny
//
//  The parts Income today and the Income tab share (SunnyIncome.dc.html, narrow): the colours and type, the logo
//  disc, the rung row (README 1.2, narrow: a 52 pt big number column, 12 apart) and the delta line.
//  Tokens (README 7): ink #F5F5F7 / #1D1D1F, muted #98989D / #6E6E73, quiet grey #AEAEB2 / #8E8E93, red #FF6961 /
//  #BC2E30, green #65C466 / #327133, on-colour text #000000 / #FFFFFF, track #2C2C2E / #E5E5EA.
//

import SwiftUI

enum IncC {
    static let ink = S.ink
    static let mu = S.secondary                                  // #98989D / #6E6E73
    static let quiet = S.dyn(0x8E8E93, 0xAEAEB2)
    static let red = S.red
    static let green = S.green
    static let onColor = S.dyn(0xFFFFFF, 0x000000)
    static let track = S.dyn(0xE5E5EA, 0x2C2C2E)
    /// rgba(29,29,31,a) light, rgba(255,255,255,a) dark: hairlines and cell fills.
    static func line(_ a: Double) -> Color { S.dynA(0x1D1D1F, a, 0xFFFFFF, a) }
    /// The banner's calls and puts (README Income: #86A8F0 and #C8946A dark, #4F7BDA and #B5794A light); a loss draws
    /// below the line in red tones, calls the brighter one.
    static let calls = S.dyn(0x4F7BDA, 0x86A8F0)
    static let puts = S.dyn(0xB5794A, 0xC8946A)
    static let callsLoss = S.dyn(0xBC2E30, 0xFF6961)
    static let putsLoss = S.dyn(0xE8928D, 0xA8433E)
    /// The picked bar's soft column.
    static let soft = S.dynA(0x000000, 0.05, 0xFFFFFF, 0.08)
    static let segTrack = S.dynA(0x767680, 0.12, 0x767680, 0.24)
    /// The page under a logo's dot (#F1F2F4 / #0A0C0B), and the 2 pt gap outside a picked logo's ring (#FFFFFF / #0A0C0B).
    static let page = S.dyn(0xF1F2F4, 0x0A0C0B)
    static let ringGap = S.dyn(0xFFFFFF, 0x0A0C0B)

    static func of(_ t: IncTone) -> Color {
        switch t { case .ink: ink; case .mu: mu; case .quiet: quiet; case .red: red; case .green: green }
    }
}

/// Inter at size/line, weight, tracking as a fraction of the size.
enum IncT {
    static func t(_ size: CGFloat, _ line: CGFloat, _ w: CGFloat = 400, tr: CGFloat = 0) -> SType { SType(size: size, weight: w, line: line, tracking: tr) }
}

/// A 1 pt rule across the top.
struct IncRule: ViewModifier {
    let a: Double
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) { Rectangle().fill(IncC.line(a)).frame(height: 1) }
    }
}
extension View {
    func incRule(_ a: Double) -> some View { modifier(IncRule(a: a)) }
}

/// The company's logo at `ratio` on a white disc; a name without a logo has its ticker in the circle.
struct IncLogo: View {
    let t: String
    let size: CGFloat
    var ratio: CGFloat = 0.6
    var body: some View {
        Circle().fill(.white)
            .overlay {
                if let img = UIImage(named: "logo-\(t)") {
                    Image(uiImage: img).resizable().scaledToFit().frame(width: size * ratio, height: size * ratio)
                } else {
                    Text(t).font(.inter(max(5, size * (size < 30 ? 0.28 : 0.21)), 800)).foregroundStyle(Color.black)
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 3)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// One rung (SunnyIncome ln9, narrow): the big kept % in a 52 pt column, 12 apart, then the title (14/19, 600, its
/// date in regular grey) with the action (13/18, 600, the big number's colour) beside it, or under it when the line is
/// too narrow, and a grey 12/16 line only for a roll or in the money. Padding 10 0, a 6% hairline on top.
struct IncLineRow: View {
    let line: IncLine
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(line.big)
                .sType(IncT.t(22, 23, 800, tr: -0.03))
                .foregroundStyle(IncC.of(line.bigTone))
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        title.fixedSize()
                        Spacer(minLength: 0)
                        action.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        title.fixedSize(horizontal: false, vertical: true)
                        action.fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let s = line.sub {
                    Text(s).sType(IncT.t(12, 16)).foregroundStyle(IncC.mu)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .incRule(0.06)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.speech)
    }

    private var title: some View {
        let sz = scales ? SDynamic.scaled(14, dts) : 14
        return Text("\(Text(line.title).foregroundStyle(IncC.of(line.titleTone)))\(Text(" · \(line.date)").font(.inter(sz, 400, tabular: true)).foregroundStyle(IncC.mu))")
            .sType(IncT.t(14, 19, 600))
    }
    private var action: some View {
        Text(line.action).sType(IncT.t(13, 18, 600)).foregroundStyle(IncC.of(line.actionTone))
    }
}

/// The delta line: the big ↑% (17 pt on Income today, 26 on a name's card), then "until NVDA turns short, at 195.72"
/// 14/19 weight 500 and one grey 12/16 line of why.
struct IncFlipView: View {
    let flip: IncName.Flip
    let bigSize: CGFloat
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(flip.big).sType(IncT.t(bigSize, (bigSize * 1.1).rounded(), 700, tr: -0.02))
                .foregroundStyle(IncC.of(flip.tone)).lineLimit(1).fixedSize()
            VStack(alignment: .leading, spacing: 1) {
                Text(flip.a).sType(IncT.t(14, 19, 500)).foregroundStyle(IncC.ink)
                if !flip.b.isEmpty { Text(flip.b).sType(IncT.t(12, 16)).foregroundStyle(IncC.mu) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(IncSay.words("\(flip.big). \(flip.a). \(flip.b)"))
    }
}
