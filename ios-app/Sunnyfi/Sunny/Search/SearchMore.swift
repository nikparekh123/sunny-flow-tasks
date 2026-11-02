//
//  SearchMore.swift
//  Sunny
//
//  Under a one-name payoff (block 30, handoff Oct 31 2026): Other payoffs, every
//  book name as a logo in a white circle (the name showing has an ink ring, a
//  name whose delta is Short or Thin a thin red or orange one), and Also helps,
//  four tiles with what the payoff can't show. A logo asks "And BABA?" and a
//  tile its own question, both as the next turn in the same chat, each with its
//  answer id. Here too: the folded answer (your question small, then the
//  answer's label and first sentence) and the logo itself.
//

import SwiftUI

struct SXMore: Decodable, Equatable {
    struct Name: Decodable, Equatable { let t: String; let co: String; let st: String? }
    struct Tile: Decodable, Equatable {
        let k: String, l: String, v: String, d: String
        let tone: String?
        /// The question it asks and its answer id; neither when the data isn't there.
        let q: String?, aid: String?
        let pend: Bool
        enum CodingKeys: String, CodingKey { case k, l, v, d, tone, q, aid = "id", pend }
        init(from dec: Decoder) throws {
            let c = try dec.container(keyedBy: CodingKeys.self)
            k = try c.decode(String.self, forKey: .k); l = try c.decode(String.self, forKey: .l)
            v = try c.decode(String.self, forKey: .v); d = try c.decode(String.self, forKey: .d)
            tone = try c.decodeIfPresent(String.self, forKey: .tone)
            q = try c.decodeIfPresent(String.self, forKey: .q); aid = try c.decodeIfPresent(String.self, forKey: .aid)
            pend = (try c.decodeIfPresent(Bool.self, forKey: .pend)) ?? false
        }
    }
    /// The name the payoff shows.
    let t: String
    let names: [Name]
    let tiles: [Tile]
}

private extension SXType {
    static let moreLabel = SXType(size: 13, line: 16, weight: .semibold, style: .footnote, tracking: 0)
    static let keyWord = SXType(size: 12, line: 16, weight: .medium, style: .caption1, tracking: 0)
    static let tileLabel = SXType(size: 13, line: 17, weight: .semibold, style: .footnote, tracking: 0)
    static let tileValue = SXType(size: 24, line: 28, weight: .bold, style: .title2, tracking: -0.01)
    static let tileLine = SXType(size: 13, line: 17, weight: .medium, style: .footnote, tracking: 0)
}

// MARK: - Other payoffs

/// A label, a two-item key on the right, then the book's logos in a row that scrolls sideways, edge to edge.
struct SXOtherPayoffs: View {
    let m: SXMore
    let ask: (_ q: String, _ id: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Other payoffs").sx(.moreLabel).foregroundStyle(SX.muted).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                HStack(spacing: 10) { key("Short", SX.down); key("Thin", SX.thin) }
                    .accessibilityHidden(true)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 4) { ForEach(m.names, id: \.t) { logo($0) } }
                    .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Other payoffs")
        }
    }

    private func key(_ word: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Color.white).overlay(Circle().strokeBorder(c.opacity(0.55), lineWidth: 1.5)).frame(width: 11, height: 11)
            Text(word).sx(.keyWord).foregroundStyle(SX.muted)
        }
    }

    /// 54 × 58 to tap; a 46 pt white circle, the logo 34 pt inside. Attention is a thin see-through ring in the flag's
    /// colour; the name showing gets an ink ring outside a 2 pt gap, and both can show together.
    private func logo(_ n: SXMore.Name) -> some View {
        let on = n.t == m.t
        let flag: Color? = n.st == "Short" ? SX.down : n.st == "Thin" ? SX.thin : nil
        return Button { if !on { ask("And \(n.t)?", "pay:\(n.t)") } } label: {
            SXLogo(t: n.t)
                .overlay(Circle().strokeBorder(flag.map { $0.opacity(0.55) } ?? Color.black.opacity(0.14), lineWidth: flag == nil ? 0.5 : 1.5))
                .shadow(color: .black.opacity(on ? 0 : 0.10), radius: 1.5, y: 1)
                .overlay {
                    if on {
                        Circle().strokeBorder(SX.paper, lineWidth: 2).frame(width: 50, height: 50)
                        Circle().strokeBorder(SX.ink, lineWidth: 2).frame(width: 54, height: 54)
                    }
                }
                .frame(width: 54, height: 58)
                .contentShape(.rect)
        }
        .buttonStyle(SXTextPress())
        .accessibilityLabel("\(n.co), \(n.t)" + (on ? ", showing" : n.st.map { ", delta \($0.lowercased())" } ?? ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A name's logo in a white circle, like the Stocks app, in light and dark; no logo, its first letter on a neutral fill.
struct SXLogo: View {
    let t: String
    var size: CGFloat = 46
    var mark: CGFloat = 34

    var body: some View {
        if let img = UIImage(named: "logo-\(t)") {
            Circle().fill(Color.white)
                .overlay(Image(uiImage: img).resizable().interpolation(.high).scaledToFit().frame(width: mark, height: mark))
                .frame(width: size, height: size)
        } else {
            Circle().fill(Color(white: 0.91))
                .overlay(Text(String(t.prefix(1))).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Color(white: 0.28)))
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Also helps

/// Four tiles in a 2 by 2, the rows the same height (at least 100): each asks its question as the next turn. A tile
/// whose data isn't there shows dashed with why, and can't be tapped.
struct SXAlsoHelps: View {
    let m: SXMore
    let ask: (_ q: String, _ id: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Also helps").sx(.moreLabel).foregroundStyle(SX.muted).accessibilityAddTraits(.isHeader)
            SXTwoUp(h: 10, v: 10, minH: 100) { ForEach(m.tiles, id: \.k) { tile($0) } }
        }
    }

    private func tile(_ x: SXMore.Tile) -> some View {
        Button { if let q = x.q, let id = x.aid { ask(q, id) } } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(x.l).sx(.tileLabel).foregroundStyle(SX.muted).lineLimit(1)
                    Spacer(minLength: 0)
                    if !x.pend { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(SX.muted) }
                }
                Text(x.v).sx(.tileValue).foregroundStyle(SX.ink).lineLimit(1).minimumScaleFactor(0.7)
                Text(x.d).sx(.tileLine).foregroundStyle(x.pend ? SX.muted : SX.tone(x.tone, SX.ink))
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if x.pend {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(SX.muted, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                } else {
                    Color.clear.modifier(SXPaper(radius: 20))
                }
            }
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(SPressStyle())
        .disabled(x.pend)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(x.l), \(x.v), \(x.d)" + (x.pend ? "" : ". Ask it."))
        .accessibilityAddTraits(x.pend ? [] : .isButton)
    }
}

/// Two across, every cell the height of the tallest (and at least minH), so a grid of tiles or widgets lines up.
struct SXTwoUp: Layout {
    var h: CGFloat = 10, v: CGFloat = 10, minH: CGFloat = 0

    private func rowH(_ w: CGFloat, _ subviews: Subviews) -> CGFloat {
        let cw = (w - h) / 2
        return max(minH, subviews.map { $0.sizeThatFits(ProposedViewSize(width: cw, height: nil)).height }.max() ?? 0)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 353, rows = (subviews.count + 1) / 2, r = rowH(w, subviews)
        return CGSize(width: w, height: CGFloat(rows) * r + CGFloat(max(0, rows - 1)) * v)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cw = (b.width - h) / 2, r = rowH(b.width, subviews)
        for (i, s) in subviews.enumerated() {
            s.place(at: CGPoint(x: b.minX + CGFloat(i % 2) * (cw + h), y: b.minY + CGFloat(i / 2) * (r + v)),
                    proposal: ProposedViewSize(width: cw, height: r))
        }
    }
}

// MARK: - A folded answer

/// Your question as a small bubble, then a card with the answer's label and first sentence, and a chevron. The
/// whole thing is one button: it opens the answer in place.
struct SXFolded: View {
    let q: String
    let label: String?
    let line: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 0) {
                    Spacer(minLength: 56)
                    Text(q).sx(SXType(size: 15, line: 20, weight: .medium, style: .subheadline, tracking: 0)).foregroundStyle(SX.muted)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 7).padding(.horizontal, 14)
                        .background(SX.fill, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18))
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let label { Text(label).sx(SXType(size: 12, line: 16, weight: .semibold, style: .caption1, tracking: 0)).foregroundStyle(SX.muted).lineLimit(1) }
                        Text(line).sx(SXType(size: 15, line: 21, weight: .regular, style: .subheadline, tracking: 0)).foregroundStyle(SX.ink)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(SX.muted).frame(width: 14)
                }
                .padding(.vertical, 12).padding(.horizontal, 16)
                .modifier(SXPaper(radius: 18))
            }
            .contentShape(.rect)
        }
        .buttonStyle(SXTextPress())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(q), folded. Tap to open.")
        .accessibilityAddTraits(.isButton)
    }
}
