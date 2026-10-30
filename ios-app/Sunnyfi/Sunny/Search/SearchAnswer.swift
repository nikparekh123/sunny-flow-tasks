//
//  SearchAnswer.swift
//  Sunny
//
//  One answer, part by part (block 27, Answer shapes and Motion): each part
//  fades up 6 pt in 0.35 s, one after another. Words of a sentence come in
//  45 ms apart, rows 70 ms apart; the next part follows 520 ms after a big
//  number, 260 ms after three numbers and 120 ms otherwise. The big number
//  counts up from 0 in 1.1 s. Reduce Motion: everything at once.
//

import SwiftUI

struct SXAnswerView: View {
    let answer: SXAnswer
    let ask: (String) -> Void

    var body: some View {
        let d = delays(answer.parts)
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(answer.parts.enumerated()), id: \.offset) { i, p in
                part(p, at: d[i]).sxRise(d[i])
            }
            if let s = answer.source { SXSourceLine(kind: s.kind, text: s.text).sxRise(d.last ?? 0) }
        }
    }

    @ViewBuilder private func part(_ p: SXPart, at t: Double) -> some View {
        switch p {
        case .say(let s): SXWords(text: s, type: .say, delay: t)
        case .body(let s): SXWords(text: s, type: .body, delay: t)
        case .big(let label, let value, let n, let count, let fmt, let sub, let tone):
            SXBig(label: label, value: value, n: n, count: count, fmt: fmt, sub: sub, tone: tone, delay: t)
        case .trio(let items): SXTrio(items: items, small: false)
        case .rows(let head, let rows): SXRows(head: head, rows: rows, panel: false, delay: t)
        case .panel(let title, let say, let trio, let rows, let table, let note, let source):
            SXPanel(title: title, say: say, trio: trio, rows: rows, table: table, note: note, source: source)
        case .web(let summary, let sources, let line): SXWeb(summary: summary, sources: sources, line: line)
        case .payoff(let p): SXPayoffCard(p: p)
        case .chart(let c): SXChartCard(p: c)
        case .book(let b): SXBookCard(p: b, ask: ask)
        case .none(let why, let dym): SXNone(why: why, didYouMean: dym, ask: ask)
        }
    }

    /// When each part starts, in seconds, and (last) when the source line does.
    private func delays(_ parts: [SXPart]) -> [Double] {
        var t = 0.0, out: [Double] = []
        for p in parts {
            out.append(t)
            switch p {
            case .say(let s), .body(let s): t += 0.12 + Double(SXWords.pieces(s)) * 0.045
            case .rows(_, let rows): t += 0.14 + Double(rows.count) * 0.07
            case .big: t += 0.52
            case .trio: t += 0.26
            default: t += 0.12
            }
        }
        out.append(t)
        return out
    }
}

// MARK: - Motion

extension View {
    /// Fades up 6 pt in 0.35 s after `delay` seconds; at once with Reduce Motion.
    func sxRise(_ delay: Double) -> some View { modifier(SXRise(delay: delay)) }
}

private struct SXRise: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduce ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 6)
            .onAppear { withAnimation(.easeOut(duration: 0.35).delay(delay)) { shown = true } }
    }
}

/// A sentence that reads in as it arrives: pieces of about three words, 45 ms apart, each fading in from a soft blur.
struct SXWords: View {
    let text: String
    let type: SXType
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var dts
    @State private var t = -1.0

    /// About three words a piece, as the design splits plain text.
    static func pieces(_ s: String) -> Int { max(1, SXText.plain(s).split(separator: " ").count / 3 + 1) }

    var body: some View {
        Text(SXText.styled(text, type, dts))
            .sx(type)
            .foregroundStyle(SX.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textRenderer(SXReveal(t: reduce ? 99 : t))
            .onAppear {
                guard t < 0, !reduce else { return }
                let total = Double(Self.pieces(text)) * 0.045 + 0.55
                t = 0
                withAnimation(.linear(duration: total).delay(delay)) { t = total }
            }
    }
}

/// Draws a text's glyphs in order, each group of about three words fading in from a 3 pt blur over 0.55 s.
struct SXReveal: TextRenderer, Animatable {
    var t: Double
    var animatableData: Double { get { t } set { t = newValue } }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        guard t < 98 else { for line in layout { ctx.draw(line) }; return }
        var i = 0
        for line in layout {
            for run in line {
                for slice in run {
                    let k = min(max((t - Double(i / 14) * 0.045) / 0.55, 0), 1)
                    i += 1
                    if k >= 1 { ctx.draw(slice); continue }
                    if k <= 0 { continue }
                    var c = ctx
                    c.opacity = k
                    c.addFilter(.blur(radius: 3 * (1 - k)))
                    c.draw(slice)
                }
            }
        }
    }
}

// MARK: - Big number

struct SXBig: View {
    @Environment(\.dynamicTypeSize) private var dts
    let label: String?, value: String, n: Double?, count: Bool, fmt: String, sub: String?, tone: String?
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = 0.0

    /// Up to 6 characters at 76, 7 to 8 at 64, 9 and more at 52. It never wraps; it steps down instead.
    private var type: SXType {
        let c = value.count
        let t = SXType(size: 76, line: 80, weight: .bold, style: .largeTitle, tracking: -0.045)
        return c <= 6 ? t : c <= 8 ? t.sized(64, line: 68) : t.sized(52, line: 56)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label { Text(label).sx(.headline).foregroundStyle(SX.ink) }
            Group {
                if count, let n { SXCount(value: shown, fmt: fmt) } else { Text(value) }
            }
            .sx(type)
            .foregroundStyle(SX.tone(tone, SX.ink))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(value)
            if let sub { Text(SXText.styled(sub, .headline, dts)).sx(.headline.weighted(.medium)).foregroundStyle(SX.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard let n else { return }
            if reduce { shown = n; return }
            // Counts up from 0 in 1.1 s, ease-out quartic.
            withAnimation(.timingCurve(0.25, 1, 0.5, 1, duration: 1.1).delay(delay)) { shown = n }
        }
    }
}

/// The count-up, frame by frame, in the big number's own format.
private struct SXCount: View, Animatable {
    var value: Double
    let fmt: String
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View {
        let v = Int(value.rounded()).formatted(.number.grouping(.automatic))
        Text(fmt == "$" ? "$" + v : v)
    }
}

// MARK: - Three numbers

struct SXTrio: View {
    @Environment(\.dynamicTypeSize) private var dts
    let items: [SXItem]
    let small: Bool
    var body: some View {
        HStack(alignment: .top, spacing: small ? 10 : 12) {
            ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, x in
                VStack(alignment: .leading, spacing: 2) {
                    Text(x.label ?? "").sx(small ? .tiny : .label).foregroundStyle(SX.muted)
                    Text(x.value ?? "").sx(small ? .trioSmall : .trio).foregroundStyle(SX.tone(x.tone, SX.ink))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let s = x.sub { Text(SXText.styled(s, small ? .tiny : .label, dts)).sx(small ? .tiny : .label).foregroundStyle(SX.tone(x.subTone, SX.muted)) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Lines

struct SXRows: View {
    @Environment(\.dynamicTypeSize) private var dts
    let head: String?
    let rows: [SXRow]
    let panel: Bool
    var delay: Double = 0

    var body: some View {
        // One scale for every bar in the list, a tenth of the span spare at each end.
        let bars = rows.compactMap(\.bar)
        let lo = bars.map(\.from).min() ?? 0, hi = bars.map(\.to).max() ?? 1, pad = (hi - lo) * 0.1
        VStack(alignment: .leading, spacing: 0) {
            if let head, !panel { Text(head).sx(.label).foregroundStyle(SX.muted).padding(.bottom, 6) }
            ForEach(Array(rows.enumerated()), id: \.offset) { j, r in
                row(r, lo: lo - pad, hi: hi + pad)
                    .modifier(RowRise(delay: panel ? 0 : delay + 0.06 + Double(j) * 0.07, on: !panel))
            }
        }
    }

    private func row(_ r: SXRow, lo: Double, hi: Double) -> some View {
        let t: SXType = panel ? .panelRow : .row
        return VStack(alignment: .leading, spacing: panel ? 3 : 2) {
            HStack(alignment: .firstTextBaseline, spacing: panel ? 12 : 14) {
                (Text(r.a ?? "").fontWeight(.semibold).foregroundColor(SX.tone(r.aTone, SX.ink))
                 + Text(SXText.styled(r.b ?? "", t, dts)).foregroundColor(SX.tone(r.bTone, SX.muted)))
                    .sx(t)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let v = r.r {
                    Text(v).sx(t.weighted(.bold)).foregroundStyle(SX.tone(r.rTone, SX.ink)).lineLimit(1).fixedSize()
                }
            }
            if let s = r.sub { Text(SXText.styled(s, panel ? .label : .small, dts)).sx(panel ? .label.weighted(.regular) : .small).foregroundStyle(SX.muted) }
            if let b = r.bar { SXRangeBar(bar: b, lo: lo, hi: hi).padding(.top, 2) }
        }
        .padding(.vertical, panel ? 10 : 11)
        .overlay(alignment: .top) { Rectangle().fill(SX.line).frame(height: 1) }
    }
}

private struct RowRise: ViewModifier {
    let delay: Double, on: Bool
    func body(content: Content) -> some View { if on { content.sxRise(delay) } else { content } }
}

/// Where a figure sits in its range: a hairline track, the range in a soft bar, the figure a dot ringed in paper.
struct SXRangeBar: View {
    let bar: SXBar, lo: Double, hi: Double
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, x = { (v: Double) in CGFloat((v - lo) / max(hi - lo, 1e-9)) * w }
            ZStack(alignment: .leading) {
                Capsule().fill(SX.track).frame(height: 2).offset(y: 0)
                Capsule().fill(SX.bar).frame(width: max(4, x(bar.to) - x(bar.from)), height: 4).offset(x: x(bar.from))
                Circle().fill(SX.ink).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(SX.paper, lineWidth: 2))
                    .position(x: x(bar.at), y: 7)
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

// MARK: - Panel (an update on one name)

struct SXPanel: View {
    @Environment(\.dynamicTypeSize) private var dts
    let title: String?, say: String?, trio: [SXItem]?, rows: [SXRow]?, table: SXTable?, note: String?, source: SXSource?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).sx(.headline.weighted(.bold)).foregroundStyle(SX.ink).accessibilityAddTraits(.isHeader) }
            if let say { Text(SXText.styled(say, .panelSay, dts)).sx(.panelSay).foregroundStyle(SX.ink).fixedSize(horizontal: false, vertical: true) }
            if let trio, !trio.isEmpty { SXTrio(items: trio, small: true) }
            if let rows, !rows.isEmpty { SXRows(head: nil, rows: rows, panel: true) }
            if let table { SXTableView(table: table) }
            if let note {
                Text(SXText.styled(note, .note, dts)).sx(.note).foregroundStyle(SX.ink)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(SX.line).frame(height: 1) }
            }
            if let source { SXSourceLine(kind: source.kind, text: source.text) }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 14, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SXPaper())
    }
}

struct SXTableView: View {
    let table: SXTable
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(Array(table.cols.enumerated()), id: \.offset) { i, c in
                    Text(c).sx(.tiny).foregroundStyle(i == 0 ? SX.ink : SX.muted).frame(width: i == 0 ? 62 : 58, alignment: .trailing)
                }
            }
            .padding(.bottom, 8)
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(r.label ?? "").sx(.tableLabel).foregroundStyle(SX.muted).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(r.values.prefix(3).enumerated()), id: \.offset) { i, v in
                        Text(v ?? "").sx(.panelRow.weighted(i == 0 ? .bold : .medium)).foregroundStyle(SX.tone(r.tone, SX.ink))
                            .lineLimit(1).minimumScaleFactor(0.7).frame(width: i == 0 ? 62 : 58, alignment: .trailing)
                    }
                }
                .padding(.vertical, 9)
                .overlay(alignment: .top) { Rectangle().fill(SX.line).frame(height: 1) }
            }
        }
    }
}

// MARK: - From the web

struct SXWeb: View {
    let summary: String, sources: [SXWebSource], line: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) { SXGlobe(); Text("From the web").sx(.time.weighted(.bold)) }.foregroundStyle(SX.web)
            SXWords(text: summary, type: .say)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sources, id: \.url) { s in
                    Link(destination: URL(string: s.url) ?? URL(string: "https://sunnyfi.co")!) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text([s.site, s.date].compactMap { $0 }.joined(separator: " · ")).sx(.time.weighted(.semibold)).foregroundStyle(SX.muted)
                            Text(s.title).sx(.headline.weighted(.medium)).foregroundStyle(SX.web).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) { Rectangle().fill(SX.line).frame(height: 1) }
                    }
                }
            }
            HStack(spacing: 6) { SXGlobe(); Text(line).sx(.source) }.foregroundStyle(SX.web)
        }
    }
}

struct SXGlobe: View {
    var body: some View {
        Image(systemName: "globe").font(.system(size: 11, weight: .bold)).frame(width: 13, height: 13).accessibilityHidden(true)
    }
}

// MARK: - Can't answer

struct SXNone: View {
    @Environment(\.dynamicTypeSize) private var dts
    let why: String?, didYouMean: String?
    let ask: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("I can’t answer that from your data.").sx(.lead).foregroundStyle(SX.ink)
                if let why { Text(SXText.styled(why, .row, dts)).sx(.row.sized(17, line: 24)).foregroundStyle(SX.muted) }
            }
            if let d = didYouMean {
                Button { ask(d) } label: {
                    HStack(spacing: 10) {
                        (Text("Did you mean ").foregroundColor(SX.muted) + Text(d).fontWeight(.semibold).foregroundColor(SX.ink) + Text("?").foregroundColor(SX.ink))
                            .sx(.field.weighted(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(SX.muted)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Source line

/// Last on every answer, always in the same place: Live (green dot with a halo), Sunny (gray dot), Last close
/// (ring), research (square), From the web (blue globe).
struct SXSourceLine: View {
    let kind: String, text: String
    var body: some View {
        HStack(spacing: 6) {
            switch kind {
            case "web": SXGlobe()
            case "live": Circle().fill(SX.up).frame(width: 7, height: 7).background(Circle().fill(SX.upTint).frame(width: 13, height: 13))
            case "close": Circle().strokeBorder(SX.muted, lineWidth: 1.5).frame(width: 7, height: 7)
            case "research": RoundedRectangle(cornerRadius: 2).strokeBorder(SX.muted, lineWidth: 1.5).frame(width: 7, height: 7)
            default: Circle().fill(SX.muted).frame(width: 7, height: 7)
            }
            Text(text).sx(.source)
        }
        .foregroundStyle(kind == "web" ? SX.web : SX.muted)
        .accessibilityElement(children: .combine)
    }
}
