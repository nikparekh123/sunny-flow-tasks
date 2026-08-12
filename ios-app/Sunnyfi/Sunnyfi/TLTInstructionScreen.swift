import SwiftUI

// MARK: - Emphasis

/// The engine ships emphasis inside its strings — `*bold*` `_underline_` `~thin~`
/// `^thick^` and `` `good` `` / `|bad|`. Parsed here rather than hard-coded in the
/// view, so a change of wording never needs a change of layout.
///
/// Hue stays off (Ink Law 1: colour is data, and none of this is data). `good` and
/// `bad` therefore render as weight, exactly as the delivered spec ships them.
enum InkMark {
    private struct Seg { var text: String; var weight: Font.Weight?; var underline = false; var thin = false }

    private static func segments(_ s: String) -> [Seg] {
        let marks: [Character: (Font.Weight?, Bool, Bool)] = [
            "*": (.semibold, false, false),
            "^": (.bold, false, false),
            "~": (.light, false, true),
            "_": (.medium, true, false),
            "`": (.semibold, false, false),
            "|": (.semibold, false, false),
        ]
        var out: [Seg] = []
        var plain = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if let m = marks[c], let close = s[s.index(after: i)...].firstIndex(of: c) {
                let inner = String(s[s.index(after: i)..<close])
                if !inner.isEmpty {
                    if !plain.isEmpty { out.append(Seg(text: plain)); plain = "" }
                    out.append(Seg(text: inner, weight: m.0, underline: m.1, thin: m.2))
                    i = s.index(after: close)
                    continue
                }
            }
            plain.append(c)
            i = s.index(after: i)
        }
        if !plain.isEmpty { out.append(Seg(text: plain)) }
        return out
    }

    static func text(_ s: String, _ size: CGFloat, _ weight: Font.Weight = .regular,
                     mono: Bool = false, dim: Color? = nil) -> Text {
        var out = Text("")
        for seg in segments(s) {
            let w = seg.weight ?? weight
            var t = Text(seg.text).font(mono ? InkFont.mono(size, w) : InkFont.display(size, w))
            if seg.underline { t = t.underline() }
            if seg.thin, let d = dim { t = t.foregroundStyle(d) }
            out = out + t
        }
        return out
    }
}

// MARK: - Card grammar

private struct TSCard<Content: View>: View {
    enum Kind { case plain, ink, fill, aside }
    var kind: Kind = .plain
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 16, leading: 17, bottom: 17, trailing: 17))
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard).strokeBorder(border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard))
            .foregroundStyle(kind == .ink ? Ink.invertText : Ink.text)
            // The aside is quiet on purpose. On a phone there is no hover to restore
            // it, so it sits a little brighter than the prototype's 0.7.
            .opacity(kind == .aside ? 0.78 : 1)
    }
    private var bg: Color {
        switch kind {
        case .plain: return Ink.surface
        case .ink:   return Ink.invertBg
        case .fill:  return Ink.text.opacity(0.09)
        case .aside: return Ink.canvas
        }
    }
    private var border: Color {
        switch kind {
        case .plain: return Ink.hair
        case .ink:   return Ink.invertBg
        case .fill:  return Ink.text.opacity(0.10)
        case .aside: return Ink.text.opacity(0.20)
        }
    }
}

private struct Eyebrow: View {
    let label: String
    var right: String? = nil
    var rightMono: Bool = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(InkFont.display(13, .medium))
            Spacer(minLength: 8)
            if let r = right {
                InkMark.text(r, rightMono ? 10 : 12.5, .regular, mono: rightMono, dim: Ink.dim)
                    .foregroundStyle(Ink.dim)
                    .textCase(rightMono ? .uppercase : nil)
            }
        }
        .frame(minHeight: 20)
    }
}

/// A clock is a rule, not a pill: at 1% of a quarter a bar is honest where a big
/// figure is not. Drawn at its true width — never seeded at zero.
private struct InkRule: View {
    let pct: Double
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Ink.text.opacity(0.14))
                Rectangle().fill(Ink.text)
                    .frame(width: max(0, min(1, pct)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Screen

struct TLTInstructionScreen: View {
    let onBack: () -> Void
    @State private var store = TLTSheetStore()
    @State private var expanded = false

    var body: some View {
        ZStack(alignment: .top) {
            Ink.canvas.ignoresSafeArea()
            if let s = store.sheet {
                sheetBody(s)
            } else {
                placeholder
            }
            titleBar
        }
        .task { await store.load() }
    }

    private var titleBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Button(action: onBack) {
                Text("TLT").font(InkFont.display(17, .semibold)).foregroundStyle(Ink.text)
            }
            .buttonStyle(.plain)
            Spacer()
            if let s = store.sheet {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(s.asOf.label).font(InkFont.display(13)).foregroundStyle(Ink.dim)
                    Text(s.asOf.refresh).font(InkFont.mono(11)).foregroundStyle(Ink.dim)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 13, trailing: 20))
        .background(Ink.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.text.opacity(0.12)).frame(height: 1) }
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            if let e = store.decodeError {
                Text("Could not read the planner").font(InkFont.display(19, .medium))
                Text(e).font(InkFont.mono(11.5)).foregroundStyle(Ink.dim)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await store.load() } }
                    .font(InkFont.mono(12)).foregroundStyle(Ink.text)
            } else {
                Text("reading the sheet").font(InkFont.mono(12)).foregroundStyle(Ink.dim)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func sheetBody(_ s: TLTSheet) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                sheetHead(s)
                hero(s.instruction)
                ladder(s.ladder)
                if let t = s.tonight { tonight(t) }
                if let h = s.holdback { holdback(h) }
                callsAside(s.calls)
                why(s.why)
                whereYouAre(s.position)
                progress(s.progress)
                ceiling(s.ceiling)
                conviction(s.conviction)
                coming(s.coming)
                book(s.book)
                sources(s.sources)
                Color.clear.frame(height: 56)
            }
            .padding(.horizontal, 17)
            .padding(.top, 62)
            // containerRelativeFrame, NOT frame(maxWidth: .infinity). maxWidth only
            // PROPOSES a width — a child that insists on being wider still overflows,
            // and a vertical ScrollView then lets the whole sheet drift sideways.
            // This pins the content to the scroll view's own width so every row has
            // to compress into it. Same law the planner pages already run on.
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load() }
    }

    // The phase belongs to the sheet, not the recommendation — it is the standing
    // intention the instruction is drawn from, so it sits on paper above the card.
    private func sheetHead(_ s: TLTSheet) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(s.phase.uppercased())
                .font(InkFont.mono(11.5)).tracking(11.5 * 0.1).foregroundStyle(Ink.dim)
            Spacer()
            if let spot = s.sources.rows.first(where: { $0.first == "Spot" }), spot.count >= 3 {
                (Text("spot ").foregroundStyle(Ink.dim) + Text(spot[2]).foregroundStyle(Ink.text))
                    .font(InkFont.mono(10.5))
            }
        }
        .padding(.top, 26).padding(.horizontal, 3)
    }

    // MARK: 1 — the instruction
    private func hero(_ i: TLTSheet.Instruction) -> some View {
        TSCard(kind: .ink) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(label: i.label).foregroundStyle(Ink.invertText.opacity(0.78))
                    Text(i.verb)
                        .font(InkFont.display(36, .medium)).tracking(36 * -0.038)
                        .lineSpacing(-2).padding(.top, 19)
                    Text(i.meta)
                        .font(InkFont.mono(12)).foregroundStyle(Ink.invertText.opacity(0.62))
                        .padding(.top, 12)

                    tierRule.padding(.top, 20)
                    HStack(alignment: .firstTextBaseline) {
                        ForEach(Array(i.commit.enumerated()), id: \.offset) { idx, pair in
                            if idx > 0 { Spacer(minLength: 14) }
                            VStack(alignment: idx == 0 ? .leading : .trailing, spacing: 3) {
                                Text(pair.first ?? "")
                                    .font(InkFont.mono(20, .medium)).monospacedDigit()
                                Text(pair.count > 1 ? pair[1] : "")
                                    .font(InkFont.display(11.5))
                                    .foregroundStyle(Ink.invertText.opacity(0.60))
                            }
                        }
                    }
                    .padding(.top, 15)

                    tierRule.padding(.top, 15)
                    // Basis is the number that matters — it is the price being paid
                    // for the shares. Credit is subordinate and never blended: under
                    // the old picker $80 of a $148 "credit" was intrinsic, i.e. money
                    // handed straight back at assignment.
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(i.basis.value)
                                .font(InkFont.mono(29, .medium)).monospacedDigit()
                            Text(i.basis.label)
                                .font(InkFont.display(12)).foregroundStyle(Ink.invertText.opacity(0.66))
                        }
                        Spacer(minLength: 14)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(i.earn.value).font(InkFont.mono(15, .medium)).monospacedDigit()
                            Text(i.earn.label)
                                .font(InkFont.display(11.5)).foregroundStyle(Ink.invertText.opacity(0.60))
                            Text(i.earn.note.uppercased())
                                .font(InkFont.mono(9.5)).tracking(9.5 * 0.02)
                                .foregroundStyle(Ink.invertText.opacity(0.60))
                        }
                    }
                    .padding(.top, 15)
                }
                if let mark = i.mark {
                    Text(mark)
                        .font(.custom("Caveat", size: 20))
                        .foregroundStyle(Ink.invertText.opacity(0.72))
                        .rotationEffect(.degrees(-4))
                        .allowsHitTesting(false)
                }
            }
        }
    }
    private var tierRule: some View { Rectangle().fill(Ink.invertText.opacity(0.18)).frame(height: 1) }

    // MARK: 2 — why this strike
    @ViewBuilder
    private func ladder(_ l: TLTSheet.Ladder) -> some View {
        TSCard {
            if let f = l.fallback {
                Eyebrow(label: l.label, right: f.state)
                Text(f.headline).font(InkFont.display(21, .medium)).padding(.top, 14)
                InkMark.text(f.note, 13.5, .regular, dim: Ink.dim)
                    .foregroundStyle(Ink.dim).padding(.top, 7)
            } else {
                Eyebrow(label: l.label)
                VStack(spacing: 0) {
                    ladderRow(l.cols.map { $0.uppercased() }, head: true, chosen: false)
                    ForEach(Array(l.rows.enumerated()), id: \.offset) { _, r in
                        ladderRow([r.strike, r.mid, r.intrinsic, r.earned, r.basis],
                                  head: false, chosen: r.chosen)
                    }
                }
                .padding(.top, 14)
                if let v = l.verdict {
                    InkMark.text(v, 14.5).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                }
            }
        }
    }

    private func ladderRow(_ cells: [String], head: Bool, chosen: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                Text(c)
                    .font(InkFont.mono(head ? 9.5 : 12.5, chosen ? .medium : .regular))
                    .monospacedDigit()
                    .tracking(head ? 9.5 * 0.08 : 0)
                    .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
            }
        }
        .foregroundStyle(head ? Ink.dim : (chosen ? Ink.text : Ink.dim))
        .padding(.vertical, head ? 0 : 9)
        .padding(.bottom, head ? 4 : 0)
        .overlay(alignment: .top) {
            if !head { Rectangle().fill(Ink.text.opacity(0.10)).frame(height: 1) }
        }
        .overlay(alignment: .leading) {
            if chosen {
                Circle().fill(Ink.text).frame(width: 4, height: 4).offset(x: -10)
            }
        }
    }

    // MARK: 3 — tonight
    private func tonight(_ t: TLTSheet.Tonight) -> some View {
        TSCard(kind: .fill) {
            Eyebrow(label: t.label, right: t.tag, rightMono: true)
            InkMark.text(t.headline, 21, .medium, dim: Ink.dim).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            bullets(t.lines).padding(.top, 14)
            if let f = t.foot {
                Rectangle().fill(Ink.text.opacity(0.12)).frame(height: 1).padding(.top, 14)
                InkMark.text(f, 14, .regular, dim: Ink.dim).padding(.top, 12)
            }
        }
    }

    private func bullets(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color.primary.opacity(0.55)).frame(width: 5, height: 5).padding(.top, 7)
                    InkMark.text(l, 14.5, .regular, dim: Ink.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: 4 — held back (above sizing, because it changed the size)
    private func holdback(_ h: TLTSheet.Holdback) -> some View {
        TSCard {
            Eyebrow(label: h.label, right: h.action.replacingOccurrences(of: "|", with: ""))
            Text(h.headline)
                .font(InkFont.display(31, .regular)).tracking(31 * -0.035).padding(.top, 9)
            InkMark.text(h.cause, 14, .regular, dim: Ink.dim).padding(.top, 9)
            InkMark.text(h.note, 13.5, .regular, dim: Ink.dim)
                .foregroundStyle(Ink.dim).padding(.top, 7)
        }
    }

    // MARK: 5 — no calls
    private func callsAside(_ c: TLTSheet.Calls) -> some View {
        TSCard(kind: .aside) {
            Eyebrow(label: c.label)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(c.lines.enumerated()), id: \.offset) { _, line in
                    (InkMark.text(line.text, 21, .medium, dim: Ink.dim)
                     + (line.emphasis.map { Text(" ") + Text($0).font(InkFont.display(21, .semibold)) } ?? Text("")))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 14)
            InkMark.text(c.note, 13.5, .regular, dim: Ink.dim)
                .foregroundStyle(Ink.dim)
                .padding(.top, 26).padding(.trailing, 60)
        }
        .padding(.top, 19)
    }

    // MARK: 6 — why this size
    private func why(_ w: TLTSheet.Why) -> some View {
        TSCard {
            Eyebrow(label: w.label)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(w.chain.enumerated()), id: \.offset) { _, step in
                    // The widest row on the sheet, and the one that was pushing
                    // everything sideways: the chain string wants ~310pt on one line
                    // and the result wants another 84, on a 359pt card. fixedSize
                    // (flexible width, ideal height) lets it wrap instead of demand.
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(step.text).font(InkFont.mono(12)).foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Text(step.out).font(InkFont.mono(14, .medium)).monospacedDigit()
                            .layoutPriority(1)
                    }
                }
            }
            .padding(.top, 15)
            Rectangle().fill(Ink.text.opacity(0.12)).frame(height: 1).padding(.top, 13)
            InkMark.text(w.verdict, 14.5).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
        }
    }

    // MARK: 7 — where you are
    private func whereYouAre(_ w: TLTSheet.Where) -> some View {
        TSCard(kind: .ink) {
            Eyebrow(label: w.label).foregroundStyle(Ink.invertText.opacity(0.78))
            InkMark.text(w.headline, 21, .medium, dim: Ink.invertText.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            bullets(w.lines).padding(.top, 14)
        }
    }

    // MARK: 8 — progress
    private func progress(_ p: TLTSheet.Progress) -> some View {
        TSCard {
            Eyebrow(label: p.label)
            VStack(alignment: .leading, spacing: 15) {
                ForEach(Array(p.rows.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(r.label).font(InkFont.display(13.5)).foregroundStyle(Ink.dim)
                            Spacer(minLength: 10)
                            Text(r.value).font(InkFont.display(13.5, .medium)).monospacedDigit()
                        }
                        InkRule(pct: r.pct).padding(.top, 8)
                        InkMark.text(r.note, 12.5, .regular, dim: Ink.dim)
                            .foregroundStyle(Ink.dim).padding(.top, 7)
                    }
                }
            }
            .padding(.top, 16)
            HStack(alignment: .firstTextBaseline) {
                Text(p.standing).font(InkFont.mono(11.5, .medium)).tracking(11.5 * 0.06)
                Spacer()
                Text(p.band).font(InkFont.mono(11.5)).tracking(11.5 * 0.03).foregroundStyle(Ink.dim)
            }
            .padding(.top, 22)
        }
    }

    // MARK: 9 — ceiling, the only thing allowed to say no
    private func ceiling(_ c: TLTSheet.Ceiling) -> some View {
        TSCard {
            Eyebrow(label: c.label, right: c.state.replacingOccurrences(of: "|", with: ""))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    (Text(c.head).foregroundStyle(Ink.dim)
                     + Text(" \(c.of)").foregroundStyle(Ink.dim.opacity(0.7)))
                        .font(InkFont.display(13.5))
                    Spacer(minLength: 10)
                    Text(c.value).font(InkFont.display(13.5, .medium)).monospacedDigit()
                }
                InkRule(pct: c.pct).padding(.top, 8)
                (InkMark.text(c.room, 12.5, .regular, dim: Ink.dim)
                 + Text(" · \(c.before)").font(InkFont.display(12.5)))
                    .foregroundStyle(Ink.dim).padding(.top, 7)
            }
            .padding(.top, 16)
            if let cut = c.cut {
                InkMark.text(cut, 14.5, .regular, dim: Ink.dim).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            }
        }
    }

    // MARK: 10 — conviction, collapsed by design
    private func conviction(_ v: TLTSheet.Conviction) -> some View {
        let top = v.families.filter(\.isTop)
        let rest = v.families.filter { !$0.isTop }
        return TSCard {
            Eyebrow(label: v.label, right: "base \(v.base) · calendar \(v.calendar)")
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text("\(v.score)").font(InkFont.display(52, .light)).monospacedDigit()
                Text("of 100").font(InkFont.display(13)).foregroundStyle(Ink.dim)
            }
            .padding(.top, 13)
            if let n = v.normalised {
                InkMark.text(n, 12.5, .regular, dim: Ink.dim)
                    .foregroundStyle(Ink.dim).padding(.top, 9)
            }
            Text(v.movers.uppercased())
                .font(InkFont.mono(9.5)).tracking(9.5 * 0.08).foregroundStyle(Ink.dim)
                .padding(.top, 15)
            VStack(spacing: 0) {
                ForEach(Array(top.enumerated()), id: \.offset) { _, f in familyRow(f, first: true) }
                if expanded {
                    ForEach(Array(rest.enumerated()), id: \.offset) { _, f in familyRow(f, first: false) }
                }
            }
            .padding(.top, 6)
            Button {
                withAnimation(.easeOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                Text(expanded ? "Fewer" : "\(rest.count) more families")
                    .font(InkFont.mono(11)).tracking(11 * 0.03)
                    .padding(.horizontal, 13).frame(minHeight: 30)
                    .overlay(Capsule().strokeBorder(Ink.text.opacity(0.22), lineWidth: 1))
                    .foregroundStyle(Ink.text)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
    }

    private func familyRow(_ f: TLTSheet.Conviction.Family, first: Bool) -> some View {
        let missing = f.down != nil
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(f.label)
                    .font(InkFont.display(14, missing || f.isDamper ? .regular : .medium))
                    .foregroundStyle(f.isDamper ? Ink.dim : Ink.text)
                Spacer(minLength: 10)
                if missing {
                    Text("NO DATA").font(InkFont.mono(10)).tracking(10 * 0.04).foregroundStyle(Ink.dim)
                } else {
                    (Text(f.score).foregroundStyle(Ink.text) + Text(" / \(f.cap)").foregroundStyle(Ink.dim))
                        .font(InkFont.mono(12)).monospacedDigit()
                }
            }
            // A damper subtracts, so its rule runs from the right and is dashed. A
            // family whose feed is down shows a dashed track with NO fill — never a
            // zero, because a zero reads as bearish rather than absent.
            familyTrack(f, missing: missing).padding(.top, 8)
            InkMark.text(f.down ?? f.read, 12.5, .regular, dim: Ink.dim)
                .foregroundStyle(missing ? Ink.text.opacity(0.9) : Ink.dim)
                .padding(.top, 6)
        }
        .padding(.top, first ? 6 : 11)
        .padding(.bottom, 12)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Ink.text.opacity(0.10)).frame(height: 1) }
        }
    }

    @ViewBuilder
    private func familyTrack(_ f: TLTSheet.Conviction.Family, missing: Bool) -> some View {
        GeometryReader { g in
            ZStack(alignment: f.isDamper ? .trailing : .leading) {
                if missing {
                    DashedLine().stroke(Ink.text.opacity(0.26), style: .init(lineWidth: 2, dash: [2, 3]))
                        .frame(height: 2)
                } else {
                    Rectangle().fill(Ink.text.opacity(0.12))
                    if f.isDamper {
                        DashedLine().stroke(Ink.text, style: .init(lineWidth: 2, dash: [3, 3]))
                            .frame(width: max(0, min(1, f.pct)) * g.size.width, height: 2)
                    } else {
                        Rectangle().fill(Ink.text)
                            .frame(width: max(0, min(1, f.pct)) * g.size.width)
                    }
                }
            }
        }
        .frame(height: 2)
    }

    // MARK: 11–13
    private func coming(_ c: TLTSheet.Coming) -> some View {
        TSCard {
            Eyebrow(label: c.label)
            VStack(spacing: 0) {
                ForEach(Array(c.events.enumerated()), id: \.offset) { i, e in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(e.date).font(InkFont.mono(12))
                            .foregroundStyle(e.isToday ? Ink.text : Ink.dim)
                            .frame(width: 56, alignment: .leading)
                        Text(e.what).font(InkFont.display(14, e.isToday ? .medium : .regular))
                        if e.isToday {
                            Text("TODAY").font(InkFont.mono(10.5)).tracking(10.5 * 0.06)
                                .foregroundStyle(Ink.dim)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(Ink.text.opacity(0.10)).frame(height: 1) }
                    }
                }
            }
            .padding(.top, 13)
        }
    }

    private func book(_ b: TLTSheet.Book) -> some View {
        TSCard {
            Eyebrow(label: b.label)
            VStack(spacing: 0) {
                ForEach(Array(b.legs.enumerated()), id: \.offset) { i, l in
                    HStack(alignment: .firstTextBaseline, spacing: 11) {
                        Text(l.qty).font(InkFont.mono(12.5)).foregroundStyle(Ink.dim)
                            .frame(width: 30, alignment: .leading)
                        Text(l.leg).font(InkFont.display(14))
                        Spacer(minLength: 8)
                        Text(l.when).font(InkFont.display(12.5)).foregroundStyle(Ink.dim)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(Ink.text.opacity(0.10)).frame(height: 1) }
                    }
                }
            }
            .padding(.top, 13)
        }
    }

    // Spot is live, FRED is daily, auctions are daily — the ages differ per source
    // and are shown per source, never as one page-level timestamp.
    private func sources(_ s: TLTSheet.Sources) -> some View {
        TSCard {
            Eyebrow(label: s.label)
            VStack(spacing: 0) {
                ForEach(Array(s.rows.enumerated()), id: \.offset) { i, r in
                    let dead = r.count > 2 && r[2] == "feed down"
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(r.first ?? "").font(InkFont.display(13)).frame(width: 66, alignment: .leading)
                        Text(r.count > 1 ? r[1] : "").font(InkFont.mono(11.5)).foregroundStyle(Ink.dim)
                        Spacer(minLength: 8)
                        Text(r.count > 2 ? r[2] : "")
                            .font(InkFont.mono(11.5))
                            .strikethrough(dead)
                            .foregroundStyle(dead ? Ink.dim : Ink.text)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(Ink.text.opacity(0.10)).frame(height: 1) }
                    }
                }
            }
            .padding(.top, 12)
        }
    }
}

private struct DashedLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}
