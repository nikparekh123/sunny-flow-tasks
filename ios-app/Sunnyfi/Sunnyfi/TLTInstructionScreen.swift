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

/// Caveat, 22pt, weight 400. Chosen because it reads as pencil rather than
/// calligraphy, and 22pt of it sits at about 15pt of the body face.
///
/// `available` exists because a missing custom font does not throw — UIFont
/// returns nil and SwiftUI quietly substitutes the system face. On a sheet where
/// the mark is deliberately the least legible thing on the page, that substitution
/// is invisible in review and wrong in production.
enum InkScript {
    static let name = "Caveat"
    static var available: Bool { UIFont(name: name, size: 12) != nil }
    static func font(_ size: CGFloat) -> Font { .custom(name, size: size) }
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
            Text(label).font(InkFont.display(15.5, .medium))
            Spacer(minLength: 8)
            if let r = right {
                InkMark.text(r, rightMono ? 13 : 15, .regular, mono: rightMono, dim: Ink.dim)
                    .foregroundStyle(Ink.dim)
                    .textCase(rightMono ? .uppercase : nil)
            }
        }
        .frame(minHeight: 22)
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

/// The boot layer. Sits UNDER the status and title bars, in the flow, so the app
/// never reads as a splash screen.
///
/// Every stage line is a real step and advances only when the engine says that step
/// resolved. Nothing here is on a timer: a progress display that moves on its own
/// is telling you something it does not know.
struct InkBoot: View {
    let stages: [String]
    let stage: Int
    let mark: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(stages.enumerated()), id: \.offset) { i, s in
                    Text(s)
                        .font(InkFont.display(18, i == stage ? .medium : .regular))
                        .tracking(18 * -0.018)
                        .foregroundStyle(Ink.text)
                        .opacity(i < stage ? 0.5 : i == stage ? (pulse ? 0.62 : 1) : 0.22)
                        .offset(y: i > stage ? 3 : 0)
                        .animation(.easeInOut(duration: 0.5), value: stage)
                }
                InkRule(pct: stages.isEmpty ? 0 : Double(stage) / Double(stages.count), height: 2)
                    .padding(.top, 34)
                    .animation(.timingCurve(0.16, 0.8, 0.24, 1, duration: 0.6), value: stage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let m = mark, AppPrefs.shared.handwriting, InkScript.available {
                Text(m).font(InkScript.font(22))
                    .foregroundStyle(Ink.text.opacity(0.6))
                    .rotationEffect(.degrees(-4))
                    .padding(.trailing, 34).padding(.bottom, 52)
                    .allowsHitTesting(false)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 34, bottom: 40, trailing: 34))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.canvas)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { pulse = true }
        }
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
            VStack(spacing: 0) {
                Color.clear.frame(height: 62)          // clears the title bar
                if let s = store.sheet {
                    sheetBody(s)
                } else if store.booting {
                    InkBoot(stages: store.stages, stage: store.stage,
                            mark: store.sheet?.boot?.mark ?? "one moment")
                } else {
                    placeholder
                }
            }
            titleBar
        }
        // Swipe horizontally to leave, same as the NVDA deck. simultaneousGesture
        // rather than gesture: this sheet scrolls VERTICALLY, and an exclusive
        // gesture would fight the scroll for every drag. The axis guard means a
        // scroll never reads as a dismiss.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { g in
                    guard abs(g.translation.width) > 80,
                          abs(g.translation.width) > abs(g.translation.height) * 1.5
                    else { return }
                    onBack()
                }
        )
        .task { await store.load() }
    }

    private var titleBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Button(action: onBack) {
                Text("TLT").font(InkFont.display(18, .semibold)).foregroundStyle(Ink.text)
            }
            .buttonStyle(.plain)
            Spacer()
            if let s = store.sheet {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(s.asOf.label).font(InkFont.display(14.5)).foregroundStyle(Ink.dim)
                    Text(s.asOf.refresh).font(InkFont.mono(13.5)).foregroundStyle(Ink.dim)
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
                .font(InkFont.mono(14)).tracking(14 * 0.1).foregroundStyle(Ink.dim)
            Spacer()
            if let spot = s.sources.rows.first(where: { $0.first == "Spot" }), spot.count >= 3 {
                (Text("spot ").foregroundStyle(Ink.dim) + Text(spot[2]).foregroundStyle(Ink.text))
                    .font(InkFont.mono(14))
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
                        .font(InkFont.display(38, .medium)).tracking(38 * -0.038)
                        .lineSpacing(-2).padding(.top, 19)
                    Text(i.meta)
                        .font(InkFont.mono(14.5)).foregroundStyle(Ink.invertText.opacity(0.62))
                        .padding(.top, 13)

                    tierRule.padding(.top, 20)
                    HStack(alignment: .firstTextBaseline) {
                        ForEach(Array(i.commit.enumerated()), id: \.offset) { idx, pair in
                            if idx > 0 { Spacer(minLength: 14) }
                            VStack(alignment: idx == 0 ? .leading : .trailing, spacing: 3) {
                                Text(pair.first ?? "")
                                    .font(InkFont.mono(23, .medium)).monospacedDigit()
                                Text(pair.count > 1 ? pair[1] : "")
                                    .font(InkFont.display(14.5))
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
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(i.basis.value)
                                .font(InkFont.mono(23, .medium)).monospacedDigit()
                            Text(i.basis.label)
                                .font(InkFont.display(14.5)).foregroundStyle(Ink.invertText.opacity(0.66))
                        }
                        Spacer(minLength: 14)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(i.earn.value).font(InkFont.mono(23, .medium)).monospacedDigit()
                            Text(i.earn.label)
                                .font(InkFont.display(14.5)).foregroundStyle(Ink.invertText.opacity(0.60))
                        }
                    }
                    .padding(.top, 15)
                }
                // A mark is never load-bearing, so an empty corner is the correct
                // fallback in all three of these cases: the engine had nothing to
                // say, the reader turned marks off, or Caveat is not bundled.
                //
                // That last one matters more than it looks. `.custom("Caveat")`
                // fails SILENTLY to the system face, which renders a straight sans
                // at 0.72 opacity and reads as a stray label rather than a note.
                // Better to show nothing than the wrong face.
                if let mark = i.mark, AppPrefs.shared.handwriting, InkScript.available {
                    Text(mark)
                        .font(InkScript.font(22))
                        .foregroundStyle(Ink.invertText.opacity(0.72))
                        .rotationEffect(.degrees(-4))
                        .allowsHitTesting(false)
                        .padding(.top, -2).padding(.trailing, 0)
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
                Text(f.headline).font(InkFont.display(23, .medium)).padding(.top, 15)
                InkMark.text(f.note, 15.5, .regular, dim: Ink.dim)
                    .foregroundStyle(Ink.dim).padding(.top, 9)
            } else {
                Eyebrow(label: l.label)
                VStack(spacing: 0) {
                    ForEach(Array(l.rows.enumerated()), id: \.offset) { idx, r in
                        ladderRow(r, first: idx == 0)
                    }
                }
                .padding(.top, 14)
                if let v = l.verdict {
                    InkMark.text(v, 16.5).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                }
            }
        }
    }

    /// Two candidates, one axis that matters: basis. No column grid, no headers.
    /// Earned is identical across candidates almost every day, so it lives in the
    /// verdict; each row carries the ONE fact that separates it. The chosen row is
    /// full ink with a left rule INSIDE the card, not a dot hanging outside it.
    private func ladderRow(_ r: TLTSheet.Ladder.Row, first: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(r.strike)
                .font(InkFont.mono(18, r.chosen ? .medium : .regular)).monospacedDigit()
                .frame(width: 52, alignment: .leading)
            Text(r.detail)
                .font(InkFont.display(15)).foregroundStyle(Ink.dim)
                .lineLimit(1)
            Spacer(minLength: 8)
            (Text("basis ").font(InkFont.display(15)).foregroundStyle(Ink.dim)
             + Text(r.basis).font(InkFont.mono(18, r.chosen ? .medium : .regular)))
                .lineLimit(1)
        }
        .foregroundStyle(r.chosen ? Ink.text : Ink.dim)
        .padding(.leading, 12)
        .padding(.top, first ? 8 : 15)
        .padding(.bottom, 16)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Ink.text.opacity(0.10)).frame(height: 1) }
        }
        .overlay(alignment: .leading) {
            if r.chosen { Rectangle().fill(Ink.text).frame(width: 2) }
        }
    }

    // MARK: 3 — tonight
    private func tonight(_ t: TLTSheet.Tonight) -> some View {
        TSCard(kind: .fill) {
            Eyebrow(label: t.label, right: t.tag, rightMono: true)
            InkMark.text(t.headline, 23, .medium, dim: Ink.dim).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            bullets(t.lines).padding(.top, 14)
            if let f = t.foot {
                Rectangle().fill(Ink.text.opacity(0.12)).frame(height: 1).padding(.top, 14)
                InkMark.text(f, 16, .regular, dim: Ink.dim).padding(.top, 13)
            }
        }
    }

    private func bullets(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color.primary.opacity(0.55)).frame(width: 5, height: 5).padding(.top, 7)
                    InkMark.text(l, 16.5, .regular, dim: Ink.dim)
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
                .font(InkFont.display(33, .regular)).tracking(33 * -0.035).padding(.top, 10)
            InkMark.text(h.cause, 16.5, .regular, dim: Ink.dim).padding(.top, 11)
            InkMark.text(h.note, 15.5, .regular, dim: Ink.dim)
                .foregroundStyle(Ink.dim).padding(.top, 9)
        }
    }

    // MARK: 5 — no calls
    private func callsAside(_ c: TLTSheet.Calls) -> some View {
        TSCard(kind: .aside) {
            Eyebrow(label: c.label)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(c.lines.enumerated()), id: \.offset) { _, line in
                    (InkMark.text(line.text, 23, .medium, dim: Ink.dim)
                     + (line.emphasis.map { Text(" ") + Text($0).font(InkFont.display(23, .semibold)) } ?? Text("")))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 14)
            InkMark.text(c.note, 15.5, .regular, dim: Ink.dim)
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
                        Text(step.text).font(InkFont.mono(14.5)).foregroundStyle(Ink.dim)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Text(step.out).font(InkFont.mono(17, .medium)).monospacedDigit()
                            .layoutPriority(1)
                    }
                }
            }
            .padding(.top, 15)
            Rectangle().fill(Ink.text.opacity(0.12)).frame(height: 1).padding(.top, 13)
            InkMark.text(w.verdict, 16.5).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
        }
    }

    // MARK: 7 — where you are
    private func whereYouAre(_ w: TLTSheet.Where) -> some View {
        TSCard(kind: .ink) {
            Eyebrow(label: w.label).foregroundStyle(Ink.invertText.opacity(0.78))
            InkMark.text(w.headline, 23, .medium, dim: Ink.invertText.opacity(0.62))
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
                            Text(r.label).font(InkFont.display(16)).foregroundStyle(Ink.dim)
                            Spacer(minLength: 10)
                            Text(r.value).font(InkFont.display(16, .medium)).monospacedDigit()
                        }
                        InkRule(pct: r.pct).padding(.top, 8)
                        InkMark.text(r.note, 15, .regular, dim: Ink.dim)
                            .foregroundStyle(Ink.dim).padding(.top, 9)
                    }
                }
            }
            .padding(.top, 16)
            HStack(alignment: .firstTextBaseline) {
                Text(p.standing).font(InkFont.mono(14, .medium)).tracking(14 * 0.06)
                Spacer()
                Text(p.band).font(InkFont.mono(14)).tracking(14 * 0.03).foregroundStyle(Ink.dim)
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
                        .font(InkFont.display(16))
                    Spacer(minLength: 10)
                    Text(c.value).font(InkFont.display(16, .medium)).monospacedDigit()
                }
                InkRule(pct: c.pct).padding(.top, 8)
                (InkMark.text(c.room, 15, .regular, dim: Ink.dim)
                 + Text(" · \(c.before)").font(InkFont.display(15)))
                    .foregroundStyle(Ink.dim).padding(.top, 7)
            }
            .padding(.top, 16)
            if let cut = c.cut {
                InkMark.text(cut, 16.5, .regular, dim: Ink.dim).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
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
                Text("\(v.score)").font(InkFont.display(56, .light)).monospacedDigit()
                Text("of 100").font(InkFont.display(15)).foregroundStyle(Ink.dim)
            }
            .padding(.top, 13)
            if let n = v.normalised {
                InkMark.text(n, 15, .regular, dim: Ink.dim)
                    .foregroundStyle(Ink.dim).padding(.top, 11)
            }
            Text(v.movers.uppercased())
                .font(InkFont.mono(13)).tracking(13 * 0.05).foregroundStyle(Ink.dim)
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
                    .font(InkFont.mono(14)).tracking(14 * 0.02)
                    .padding(.horizontal, 17).frame(minHeight: 40)
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
                    .font(InkFont.display(16.5, missing || f.isDamper ? .regular : .medium))
                    .foregroundStyle(f.isDamper ? Ink.dim : Ink.text)
                Spacer(minLength: 10)
                if missing {
                    Text("NO DATA").font(InkFont.mono(13)).tracking(13 * 0.04).foregroundStyle(Ink.dim)
                } else {
                    (Text(f.score).foregroundStyle(Ink.text) + Text(" / \(f.cap)").foregroundStyle(Ink.dim))
                        .font(InkFont.mono(14.5)).monospacedDigit()
                }
            }
            // A damper subtracts, so its rule runs from the right and is dashed. A
            // family whose feed is down shows a dashed track with NO fill — never a
            // zero, because a zero reads as bearish rather than absent.
            familyTrack(f, missing: missing).padding(.top, 8)
            InkMark.text(f.down ?? f.read, 15, .regular, dim: Ink.dim)
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
                        Text(e.date).font(InkFont.mono(14.5))
                            .foregroundStyle(e.isToday ? Ink.text : Ink.dim)
                            .frame(width: 72, alignment: .leading)
                        Text(e.what).font(InkFont.display(16.5, e.isToday ? .medium : .regular))
                        if e.isToday {
                            Text("TODAY").font(InkFont.mono(13)).tracking(13 * 0.04)
                                .foregroundStyle(Ink.dim)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 13)
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
                        Text(l.qty).font(InkFont.mono(15)).foregroundStyle(Ink.dim)
                            .frame(width: 40, alignment: .leading)
                        Text(l.leg).font(InkFont.display(16.5))
                        Spacer(minLength: 8)
                        Text(l.when).font(InkFont.display(14.5)).foregroundStyle(Ink.dim)
                    }
                    .padding(.vertical, 13)
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
                        Text(r.first ?? "").font(InkFont.display(15.5)).frame(width: 84, alignment: .leading)
                        Text(r.count > 1 ? r[1] : "").font(InkFont.mono(14)).foregroundStyle(Ink.dim)
                        Spacer(minLength: 8)
                        Text(r.count > 2 ? r[2] : "")
                            .font(InkFont.mono(14))
                            .strikethrough(dead)
                            .foregroundStyle(dead ? Ink.dim : Ink.text)
                    }
                    .padding(.vertical, 11)
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
