//
//  IncParts.swift
//  Sunny
//
//  The parts Income today and the Income tab share (SunnyIncome.dc.html and SunnyIncomeCal.dc.html, narrow): the
//  colours and type, the logo disc, Income today's rung row (README 1.2, narrow: a 52 pt big number column, 12 apart)
//  and its delta line.
//  Tokens (README 7): ink #F5F5F7 / #1D1D1F, muted #98989D / #6E6E73, quiet grey #AEAEB2 / #8E8E93, red #FF6961 /
//  #BC2E30, green #65C466 / #327133, on-colour text #000000 / #FFFFFF, track #2C2C2E / #E5E5EA.
//  The focus look (handoff 2026-11-25-focus): red and green are marks only (IncC.of: dots, rings); on words and
//  numbers a tone goes through IncC.word (ink at 15 pt and up, grey under).
//

import SwiftUI

enum IncC {
    static let ink = S.ink
    static let mu = S.secondary                                  // #98989D / #6E6E73
    static let quiet = S.dyn(0x8C8C8C, 0xAAAAAA)
    static let red = S.red
    static let green = S.green
    static let onColor = S.dyn(0xFAFAFA, 0x171717)
    static let track = S.dyn(0xE6E6E6, 0x2A2A2A)
    /// rgba(29,29,31,a) light, rgba(255,255,255,a) dark: hairlines and cell fills.
    static func line(_ a: Double) -> Color { S.dynA(0x212121, a, 0xFAFAFA, a) }
    /// The banner's calls and puts (README Income: #86A8F0 and #C8946A dark, #4F7BDA and #B5794A light); a loss draws
    /// below the line in red tones, calls the brighter one.
    static let calls = S.dyn(0x3E6AE1, 0x3E6AE1)
    static let puts = S.dyn(0xB5794A, 0xC8946A)
    static let callsLoss = S.dyn(0xCC0000, 0xE82127)
    static let putsLoss = S.dyn(0xE8928D, 0xA8433E)
    /// The picked bar's soft column.
    static let soft = S.dynA(0x171717, 0.05, 0xFAFAFA, 0.08)
    static let segTrack = S.dynA(0x808080, 0.12, 0x808080, 0.24)
    /// The calendar (SunnyIncomeCal T): a tile and a filled day rgba(29,29,31,.035) / rgba(255,255,255,.04); the dashed
    /// landing day ln(.3) / ln(.28); a picked pill's thumb #FFFFFF / rgba(255,255,255,.2); a logo's light ring
    /// inset .5px rgba(29,29,31,.14), none in dark.
    static let tile = S.dynA(0x212121, 0.035, 0xFAFAFA, 0.04)
    static let dash = S.dynA(0x212121, 0.3, 0xFAFAFA, 0.28)
    static let thumb = S.dynA(0xFAFAFA, 1, 0xFAFAFA, 0.2)
    static let logoRing = S.dynA(0x212121, 0.14, 0xFAFAFA, 0)
    /// A ready rung's ring: 1 px rgba(50,113,51,.5) / rgba(101,196,102,.65).
    static let actRing = S.dynA(0x1C7840, 0.5, 0x4CBB6C, 0.65)

    /// A tone as a mark (a dot, a ring): red and green stay.
    static func of(_ t: IncTone) -> Color {
        switch t { case .ink: ink; case .mu: mu; case .quiet: quiet; case .red: red; case .green: green }
    }
    /// A tone on words or numbers (focus §2.1): never red or green; what was is ink at 15 pt and up, grey under.
    static func word(_ t: IncTone, _ size: CGFloat) -> Color {
        t == .red || t == .green ? SF.word(size) : of(t)
    }
    /// The rare dot a tone keeps before a value (§2.3): red danger, green ready to act.
    static func dot(_ t: IncTone) -> SF.Dot? { t == .red ? .danger : t == .green ? .act : nil }
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

/// The company's logo at `ratio` on a white disc; a name without a logo has its ticker in the circle. `ring`: the
/// calendar's .5 pt hairline in light (none in dark).
struct IncLogo: View {
    let t: String
    let size: CGFloat
    var ratio: CGFloat = 0.6
    var ring = false
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
            .overlay { if ring { Circle().strokeBorder(IncC.logoRing, lineWidth: 0.5) } }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// One rung (SunnyIncome ln9, narrow): the big kept % in a 52 pt column, 12 apart, then the title (14/19, 600, its
/// date in regular grey) with the action (13/18, 600) beside it, or under it when the line is too narrow, and a grey
/// 12/16 line only for a roll or in the money. Padding 10 0, a 6% hairline on top. Focus: the % and the action lose
/// their red and green (ink, grey under 15 pt; a loss reads "−12%"); the group title above carries the dot.
struct IncLineRow: View {
    let line: IncLine
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(line.big)
                .sType(IncT.t(22, 23, 800, tr: -0.03))
                .foregroundStyle(IncC.word(line.bigTone, 22))
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
        return Text("\(Text(line.title).foregroundStyle(IncC.word(line.titleTone, 14)))\(Text(" · \(line.date)").font(.inter(sz, 400, tabular: true)).foregroundStyle(IncC.mu))")
            .sType(IncT.t(14, 19, 600))
    }
    private var action: some View {
        Text(line.action).sType(IncT.t(13, 18, 600)).foregroundStyle(IncC.word(line.actionTone, 13))
    }
}

/// The delta line: the big ↑% (17 pt on Income today, 26 on a name's card), then "until NVDA turns short, at 195.72"
/// 14/19 weight 500 and one grey 12/16 line of why. Focus: the big figure is never red; close to turning short it
/// keeps the red dot, on a word ("Now") or a figure 20 pt and up (§2.3).
struct IncFlipView: View {
    let flip: IncName.Flip
    let bigSize: CGFloat
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .center, spacing: 0) {
                if flip.tone == .red && (bigSize >= 20 || flip.big.contains(where: \.isLetter)) { SDot(kind: .danger) }
                Text(flip.big).sType(IncT.t(bigSize, (bigSize * 1.1).rounded(), 700, tr: -0.02))
                    .foregroundStyle(IncC.word(flip.tone, bigSize)).lineLimit(1)
            }
            .fixedSize()
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
