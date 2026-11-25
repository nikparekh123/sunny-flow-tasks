//
//  IncCalendar.swift
//  Sunny
//
//  The Income calendar on the Income tab (handoff 2026-11-24 late §1.3; SunnyIncomeCal.dc.html with the app's props
//  head false, narrow, view m, views m, quiet fold), under the realized banner. Top to bottom, 14 apart:
//    · the ticker strip, like the account strip: All, then Nicolay's names, a hairline, then Sunny's (one account: All,
//      a hairline, its names). A 3 pt track, pills 36 tall (13 pt, a 26 pt logo, a 7 pt dot red in the money, green
//      ready to act); the picked one on the thumb. It scrolls sideways when it runs long.
//    · the status line between hairlines, on one row: left the name (or All) 17/22 bold, truncating, and one grey line;
//      right the big count that needs you (30 pt, red if any is in the money, else green) with "need you" 17/22, and
//      "1 in the money · 1 to roll" grey; "All quiet" grey with the nearest roll when nothing needs you.
//    · the range: "Nov 23 to Dec 18" 15/22 bold over "4 weeks · today Tue Nov 24" 12/16 grey.
//    · the grid on the flat card (radius 20): M T W T F, then four weeks of compact days 66 tall (the day's pill, one
//      word or % and a count; on All how many need you), the landing day dashed, today an ink circle, past days and
//      the market holiday faded. Every day with something on it opens fully under its week: on one name a tile a rung
//      (strike ×count, the big % kept, the action, one grey line) and the dashed next rung with its strike and
//      premium; on All a line a name (a tap opens that name on the strip) and the quiet names behind one grey line.
//  No explanation lines, no em dashes, no minus signs.
//

import SwiftUI

struct IncCalView: View {
    let cal: IncCal
    let names: [IncName]
    let account: BriefAccount
    /// The market holidays in the app's calendar (added to the ones the income payload marks).
    let closed: Set<String>
    /// The picked ticker; nil is All.
    @Binding var tk: String?
    /// A name's line tapped on All: the tab switches the strip to it.
    let open: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    private var one: IncName? { tk.flatMap { t in names.first { $0.t == t } } }

    var body: some View {
        let sc = cal.scope(one?.t)
        VStack(alignment: .leading, spacing: 14) {
            strip
            status(sc.status)
            range
            grid(sc)
        }
    }

    // MARK: The ticker strip

    /// All, then Nicolay's names, then Sunny's (Together); one account: its names.
    private var groups: [[IncName]] {
        guard account == .together else { return [names] }
        let b = names.filter { $0.books.contains("Nicolay") }
        let a = names.filter { !$0.books.contains("Nicolay") }
        return [b, a].filter { !$0.isEmpty }
    }

    @State private var stripW: CGFloat = 0

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    pill(nil, "All", dot: nil)
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                        Rectangle().fill(IncC.line(0.16)).frame(width: 1, height: 20).padding(.horizontal, 6)
                            .accessibilityHidden(true)
                        ForEach(g) { n in pill(n.t, n.t, dot: n.dot, co: n.co) }
                    }
                }
                .padding(3)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripW = $0 }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(maxWidth: stripW > 0 ? stripW : nil, alignment: .leading)
            .background(Capsule().fill(IncC.segTrack))
            .clipShape(.capsule)
            .onChange(of: tk) { _, t in
                withAnimation(S.fade) { proxy.scrollTo(t ?? "All") }
            }
        }
        .sensoryFeedback(.selection, trigger: tk)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ticker")
    }

    private func pill(_ key: String?, _ label: String, dot: IncTone?, co: String? = nil) -> some View {
        let on = key == one?.t
        let dark = scheme == .dark
        return Button {
            guard !on else { return }
            tk = key
        } label: {
            HStack(spacing: 7) {
                if key != nil { IncLogo(t: label, size: 26, ring: true) }
                Text(label).sType(IncT.t(13, 16, on ? 600 : 500), tabular: false)
                    .foregroundStyle(on ? IncC.ink : IncC.mu)
                    .lineLimit(1).fixedSize()
                if let dot { Circle().fill(IncC.of(dot)).frame(width: 7, height: 7) }
            }
            .padding(.leading, key == nil ? 15 : 5).padding(.trailing, 13)
            .frame(height: 36)
            .background {
                // The thumb: #FFFFFF with 0 1px 3px rgba(0,0,0,.12) and a .5 px 4% ring in light; rgba(255,255,255,.2)
                // with an inset .5 px 22% ring and 0 2px 8px rgba(0,0,0,.35) in dark. Fades .2 s.
                Capsule().fill(IncC.thumb)
                    .overlay { Capsule().strokeBorder(dark ? Color.white.opacity(0.22) : Color.clear, lineWidth: 0.5) }
                    .overlay { if !dark { Capsule().stroke(Color.black.opacity(0.04), lineWidth: 0.5) } }
                    .shadow(color: .black.opacity(dark ? 0.35 : 0.12), radius: dark ? 4 : 1.5, y: dark ? 2 : 1)
                    .opacity(on ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: on)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .id(key ?? "All")
        .accessibilityLabel(key == nil ? "All names" : (co ?? label) + (dot == .red ? ", in the money" : dot == .green ? ", needs you" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: The status line

    private func status(_ s: IncCal.Status) -> some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                if let n = one { IncLogo(t: n.t, size: 36, ring: true) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctxT).sType(IncT.t(17, 22, 700, tr: -0.01), tabular: false).foregroundStyle(IncC.ink)
                        .lineLimit(1).truncationMode(.tail)
                    Text(ctxS).sType(IncT.t(13, 18)).foregroundStyle(IncC.mu)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if s.need > 0 {
                        Text("\(s.need)").sType(IncT.t(30, 34, 800, tr: -0.03)).foregroundStyle(IncC.of(s.tone))
                    }
                    Text(s.word).sType(IncT.t(17, 22, 600), tabular: false).foregroundStyle(s.need > 0 ? IncC.ink : IncC.quiet)
                }
                Text(s.sub).sType(IncT.t(13, 18)).foregroundStyle(IncC.mu)
            }
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(IncSay.words((s.need > 0 ? "\(s.need) \(s.word)" : s.word) + ". " + s.sub))
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .incRule(0.08)
        .overlay(alignment: .bottom) { Rectangle().fill(IncC.line(0.08)).frame(height: 1) }
    }

    /// "NVDA · Nvidia", "All names" (Together), "Sunny’s names".
    private var ctxT: String {
        if let n = one { return n.co == n.t ? n.t : "\(n.t) · \(n.co)" }
        return account == .together ? "All names" : "\(account.name)’s names"
    }
    /// "$177.20 · ↑0.4% today · Nicolay · ladder", "6 names · Sunny and Nicolay".
    private var ctxS: String {
        if let n = one {
            var p = ["$" + IncFmt.f2(n.px)]
            if let c = n.chg { p.append("\(c >= 0 ? "↑" : "↓")\(String(format: "%.1f", abs(c)))% today") }
            if account == .together, !n.books.isEmpty { p.append(IncCal.and(n.books)) }
            p.append(n.ladder ? "ladder" : "weekly")
            // A no-break space before each dot, so a wrapped line never starts with "·".
            return p.joined(separator: "\u{00A0}· ")
        }
        return "\(names.count) \(names.count == 1 ? "name" : "names")" + (account == .together ? " · Sunny and Nicolay" : "")
    }

    // MARK: The range

    private var range: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(cal.range).sType(IncT.t(15, 22, 700)).foregroundStyle(IncC.ink).lineLimit(1)
            Text(cal.rangeSub).sType(IncT.t(12, 16)).foregroundStyle(IncC.mu).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: The grid

    private func grid(_ sc: IncCal.Scope) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Array(["M", "T", "W", "T", "F"].enumerated()), id: \.offset) { _, l in
                    Text(l).sType(IncT.t(12, 16, 600, tr: 0.05), tabular: false).foregroundStyle(IncC.mu)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 6, bottom: 2, trailing: 6))
            .accessibilityHidden(true)
            VStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { w in week(w, sc) }
            }
            .padding(EdgeInsets(top: 4, leading: 6, bottom: 8, trailing: 6))
        }
        .frame(maxWidth: .infinity)
        .sunnyGlass(radius: 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Income calendar, \(ctxT), \(cal.range)")
    }

    private func week(_ w: Int, _ sc: IncCal.Scope) -> some View {
        let ds = cal.days.filter { $0.w == w }
        return VStack(spacing: 6) {
            // 66 tall at the default text size; with larger text the row grows, every day as tall as the tallest.
            HStack(spacing: 4) {
                ForEach(ds) { d in cell(d, sc.boxes[d.id]) }
            }
            .fixedSize(horizontal: false, vertical: true)
            ForEach(ds.filter { !sc.boxes[$0.id].empty }) { d in
                openDay(d, sc.boxes[d.id])
                    .padding(.horizontal, -6)
            }
        }
    }

    /// A compact day: 66 tall, padding 6 2 5 inside a 1 pt border (dashed on the landing day), radius 12, the tile
    /// fill when something expires; the day's pill (24 tall, 12 pt; today an ink circle), the word or count 14/17
    /// bold, the small word 10/12 grey. Past days and the holiday fade to .45.
    private func cell(_ d: IncCal.Day, _ b: IncCal.Box) -> some View {
        let shut = d.closed || closed.contains(d.iso)
        let faded = d.past || shut
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let sm = b.sm.isEmpty && shut ? "closed" : b.sm
        return VStack(spacing: 2) {
            Text(d.pill)
                .font(.inter(12, d.today ? 700 : 500, tabular: true))
                .foregroundStyle(d.today ? IncC.onColor : faded ? IncC.mu : IncC.ink)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 6)
                .frame(minWidth: 24, minHeight: 24)
                .background(Capsule().fill(d.today ? IncC.ink : .clear))
                .opacity(faded ? 0.45 : 1)
            if b.big.isEmpty { Color.clear.frame(height: 0) } else {
                Text(b.big).sType(IncT.t(14, 17, 700)).foregroundStyle(IncC.of(b.bigTone))
                    .lineLimit(1).fixedSize()
                    .opacity(faded ? 0.45 : 1)
            }
            if !sm.isEmpty {
                Text(sm).sType(IncT.t(10, 12), tabular: false).foregroundStyle(IncC.mu).lineLimit(1).fixedSize()
            }
        }
        .padding(EdgeInsets(top: 7, leading: 3, bottom: 6, trailing: 3))
        .frame(maxWidth: .infinity, minHeight: 66, maxHeight: .infinity, alignment: .top)
        .background(shape.fill(b.filled ? IncC.tile : .clear))
        .overlay { if b.dashed { shape.strokeBorder(IncC.dash, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(b.speech + (shut && !b.speech.contains("closed") ? ", market closed" : ""))
    }

    /// A day opened under its week: a hairline across the card, padding 12 14 14, 10 apart: "Tue Nov 24 · today"
    /// 15/20 bold, then the tiles (one name) or the lines (All), the quiet names' grey line, the dashed next rung.
    private func openDay(_ d: IncCal.Day, _ b: IncCal.Box) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(d.title).sType(IncT.t(15, 20, 700), tabular: false).foregroundStyle(IncC.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(b.legs) { tile($0) }
            ForEach(b.rows) { row($0) }
            if let m = b.more {
                Text(m).sType(IncT.t(12, 16), tabular: false).foregroundStyle(IncC.mu)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(b.nx) { nextBox($0) }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .incRule(0.08)
        .accessibilityElement(children: .contain)
    }

    /// A rung: padding 10 12 11, radius 14, the tile fill and its ring (1.5 pt red in the money, 1 pt green to roll,
    /// a 6% hairline running). "167.5 call ×3" 13/18 grey; the % kept 26 pt heavy with "kept" 13/18 grey; the action
    /// 13/18 semibold in the %'s colour; one grey 12/16 line.
    private func tile(_ l: IncCal.Leg) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let ring: Color = l.ring == .itm ? IncC.red : l.ring == .act ? IncC.actRing : IncC.line(0.06)
        return VStack(alignment: .leading, spacing: 2) {
            Text(l.lab).sType(IncT.t(13, 18)).foregroundStyle(IncC.mu).lineLimit(1).truncationMode(.tail)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !l.big.isEmpty {
                    Text(l.big).sType(IncT.t(26, 29, 800, tr: -0.03)).foregroundStyle(IncC.of(l.tone)).lineLimit(1).fixedSize()
                }
                Text(l.bw).sType(IncT.t(13, 18), tabular: false).foregroundStyle(IncC.mu)
            }
            // Inter is one variable font: the semibold is its own font (fontWeight cannot reach the weight axis).
            (Text(l.premSold).font(.inter(12, 600, tabular: true)).foregroundStyle(IncC.ink) + Text(" premium · ")
             + Text(l.premLeft).font(.inter(12, 600, tabular: true)).foregroundStyle(IncC.ink) + Text(" to collect"))
                .sType(IncT.t(12, 16)).foregroundStyle(IncC.mu).lineLimit(1).minimumScaleFactor(0.85)
            if let a = l.act {
                Text(a).sType(IncT.t(13, 18, 600)).foregroundStyle(IncC.of(l.tone))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            if let s = l.sub {
                Text(s).sType(IncT.t(12, 16)).foregroundStyle(IncC.mu)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 11, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(IncC.tile))
        .overlay(shape.strokeBorder(ring, lineWidth: l.ring == .itm ? 1.5 : 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l.speech)
    }

    /// A name on All: the 28 pt logo, the ticker 15/20 semibold (grey when it runs on its own), the word 15/20 bold in
    /// its colour, at least 44 tall; the strike and action 12/16 grey under the ticker. A tap opens the name.
    private func row(_ r: IncCal.Row) -> some View {
        Button { open(r.t) } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .center, spacing: 10) {
                    IncLogo(t: r.t, size: 28, ring: true)
                    Text(r.t).sType(IncT.t(15, 20, 600), tabular: false).foregroundStyle(IncC.of(r.tTone))
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.word).sType(IncT.t(15, 20, 700)).foregroundStyle(IncC.of(r.wTone)).lineLimit(1).fixedSize()
                }
                Text(r.why).sType(IncT.t(12, 16)).foregroundStyle(IncC.mu)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 38)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(IncPress())
        .accessibilityLabel(r.speech)
        .accessibilityHint("Opens \(r.t)")
    }

    /// The next rung: a 1 pt dashed box, radius 14, padding 8 12 9; "Next · from Nov 27’s 167.5 call" 12/16 grey over
    /// "157.5 call · 7.50" 14/19 semibold quiet grey.
    private func nextBox(_ z: IncCal.Next) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(z.top).sType(IncT.t(12, 16)).foregroundStyle(IncC.mu).fixedSize(horizontal: false, vertical: true)
            Text(z.main).sType(IncT.t(14, 19, 600)).foregroundStyle(IncC.quiet).fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 9, leading: 13, bottom: 10, trailing: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(IncC.dash, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        .accessibilityElement(children: .combine)
    }
}

/// A row's press: .75 opacity while held (the design's hover).
struct IncPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}
