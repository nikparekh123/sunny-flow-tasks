//
//  PlannerPages.swift
//  Six snap pages, one decision each, in the order a seller decides:
//  how strong is the setup (00), what could break the week (01), is the floor
//  intact (02), what to sell (03), what is running (04, only once a sale is
//  confirmed), and the one input no feed provides (05).
//
//  There used to be a seventh — "the decision" — whose whole content was that
//  conviction sized the sale to 44 where a neutral read would sell 62. A screen
//  for one comparison against a hypothetical, and the comparison did not read.
//  It is a clause on the tier it describes now. What it carried that mattered —
//  the open position, and the grade footer — moved to the sell page and to
//  conviction, where grade is one of the nine families anyway.
//
//  Every page is a PPPage. None of them positions its own hero — that is the
//  layout law's job, stated once in PlannerPagesKit.
//
//  Design source: docs/design/planner_pages/.
//

import SwiftUI

private let f2: (Double) -> String = { String(format: "%.2f", $0) }
private let f1: (Double) -> String = { String(format: "%.1f", $0) }
private func sgn(_ v: Double, _ dp: Int = 0) -> String {
    (v < 0 ? "−" : "+") + String(format: "%.\(dp)f", abs(v))
}
private func grouped(_ v: Double) -> String {
    let fm = NumberFormatter(); fm.numberStyle = .decimal; fm.maximumFractionDigits = 0
    return fm.string(from: NSNumber(value: v)) ?? String(Int(v))
}

// MARK: - 00 · Conviction (paper)

/// Audit the number before trusting it. Nine equal discs — size says nothing,
/// weight is carried by colour depth. Solid adds conviction, hollow takes it
/// away, dashed means the slot exists and the number does not.
struct PPConvictionPage: View {
    let r: PPResponse
    var toGrade: (() -> Void)? = nil
    @State private var selected: String? = nil

    private var discs: [PPDisc] { r.discsOrdered() }
    private var sel: PPDisc? { discs.first { $0.id == selected } }

    var body: some View {
        PPPage(ground: .paper) {
            Text(Self.dateLine().uppercased())
                .font(PP.mono(12)).tracking(12 * 0.18)
                .foregroundStyle(PP.dim(.paper))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                      spacing: 12) {
                ForEach(discs) { d in
                    PPDiscView(disc: d, selected: selected == d.id)
                        .onTapGesture { selected = (selected == d.id) ? nil : d.id }
                }
            }
        } base: {
            if let d = sel {
                PPNum(value: d.computed ? sgn(d.today) : "—",
                      unit: "of \(Int(d.family.cap))",
                      size: 96, hue: PP.familyHue[d.family.key], ground: .paper)
                PPTrail(values: d.series.map { sgn($0) }, ground: .paper)
                PPSay(text: d.moved == 0
                      ? "Flat since the last reading."
                      : "\(d.moved > 0 ? "Added" : "Took back") \(Int(abs(d.moved).rounded())) on the last reading.",
                      ground: .paper)
                PPFine(text: d.family.reads, ground: .paper)
            } else {
                PPNum(value: "\(r.plan?.conviction ?? 0)", unit: "of 100", ground: .paper)
                PPTrail(values: (r.history?.trail ?? []).map { "\($0.conviction ?? 0)" },
                        ground: .paper)
                PPSay(text: r.moversLine(), ground: .paper)
            }
            VStack(spacing: 0) {
                Rectangle().fill(PP.hairline(.paper)).frame(height: 1)
                Button { toGrade?() } label: {
                    HStack {
                        // The neutral 50 the score is measured from — which is the
                        // only thing that makes the grade beside it legible.
                        Text("baseline 50".uppercased())
                        Spacer()
                        Text("your grade \(sgn(r.discs().first { $0.id == "grade" }?.today ?? 0))".uppercased())
                    }
                    .font(PP.mono(11)).tracking(11 * 0.14)
                    .foregroundStyle(PP.dim(.paper))
                }
                .disabled(toGrade == nil)
                .padding(.top, 13)
            }
            .padding(.top, 20)
        }
    }

    private static func dateLine() -> String {
        let fm = DateFormatter(); fm.dateFormat = "EEEE, d MMM"
        return fm.string(from: Date())
    }
}

private struct PPDiscView: View {
    let disc: PPDisc
    let selected: Bool

    /// Solid when the family is adding, a ring when it is taking away. The mix
    /// is toward white so depth reads as weight on the paper ground.
    private var fill: Color {
        (PP.familyHue[disc.family.key] ?? .gray)
            .opacity(0.26 + 0.74 * disc.strength)
    }

    var body: some View {
        ZStack {
            if !disc.computed {
                Circle().strokeBorder(fill, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            } else if disc.today < 0 {
                Circle().strokeBorder(fill, lineWidth: 3)
            } else if disc.today == 0 {
                Circle().strokeBorder(fill.opacity(0.48), lineWidth: 1.5)
            } else {
                Circle().fill(fill)
            }
            if selected {
                Text(disc.family.key.uppercased())
                    .font(PP.mono(10)).tracking(10 * 0.14)
                    // Reads off the measured luminance of the mix, never off the
                    // weight that made it, so the label always survives.
                    .foregroundStyle(disc.today > 0 && disc.strength > 0.55 ? .white : PP.paperText)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 106)
        // A stroked circle's hit area is the STROKE — a 1.5pt ring, and nothing
        // inside it. So the four families drawn as outlines (negative, zero, and
        // the no-feed dashed one) could only be tapped by hitting the line itself,
        // while the solid ones worked everywhere. Same shape, same target.
        .contentShape(Circle())
        .overlay(selected ? Circle().strokeBorder(PP.paperText, lineWidth: 2) : nil)
        .animation(.easeInOut(duration: 0.3), value: selected)
    }
}

// MARK: - 02 · The week (ink)

/// The only page with no hero: it is all content. The quiet list stays visible
/// and faded — nothing is hidden.
struct PPWeekPage: View {
    let r: PPResponse

    var body: some View {
        PPPage(ground: .ink) {
            PPKicker(text: "what matters this week", ground: .ink)
            PPNoteList(rows: r.observations?.matters ?? [], quiet: false)
            if !(r.observations?.quiet ?? []).isEmpty {
                PPKicker(text: "what won't matter", ground: .ink).padding(.top, 8)
                PPNoteList(rows: r.observations?.quiet ?? [], quiet: true)
            }
        } base: { EmptyView() }
    }
}

private struct PPNoteList: View {
    let rows: [PPNote]
    let quiet: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, n in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)").font(PP.mono(12))
                        .foregroundStyle(PP.dim(.ink)).frame(width: 13, alignment: .leading)
                    (Text(n.heading).font(PP.disp(quiet ? 15 : 16, .semibold))
                        .foregroundStyle(PP.inkText)
                     + Text(" " + (n.text ?? "")).font(PP.disp(quiet ? 15 : 16))
                        .foregroundStyle(PP.dim(.ink)))
                    .lineSpacing((quiet ? 15 : 16) * 0.45)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 02 · Put floor (ink)

/// The floor is a SLEEVE, not a blanket. It covers 2,500 of 7,500 shares, so below
/// it the position keeps falling — just more slowly. The chart exists to make that
/// unmistakable: the kink is where protection starts, and the gap between the two
/// slopes is what the premium bought. Calling this book "protected" would be the
/// most dangerous thing the page could imply.
struct PPFloorPage: View {
    let r: PPResponse

    var body: some View {
        let fl = r.floorAdvice
        PPPage(ground: .ink) {
            HStack(alignment: .firstTextBaseline) {
                PPKicker(text: "put floor", ground: .ink)
                Spacer()
                if let d = fl?.days, let e = fl?.expiry {
                    Text("\(d)d to \(e)".uppercased())
                        .font(PP.mono(10.5)).tracking(10.5 * 0.08)
                        .foregroundStyle(PP.dim(.ink))
                }
            }
            if let pay = fl?.payoff, let pts = pay.points, pts.count >= 3 {
                PPFloorChart(pay: pay, fl: fl, shares: r.book?.shares ?? 0)
                PPFine(text: "Below \(Int(fl?.floor ?? 0)) the line keeps falling — the floor covers "
                       + "\(grouped(fl?.covers ?? 0)) shares, not the book. What it buys is the "
                       + "shallower slope, not a flat one.", ground: .ink, topPad: 0)
            }
        } base: {
            PPNum(value: fl?.floor.map { String(Int($0)) } ?? "—",
                  unit: fl?.gapLine, size: 92, ground: .ink)
            PPSay(text: (fl?.verdict ?? "No floor set").appendingPeriod(), ground: .ink)
            PPFine(text: "The floor is rolled first, as its own decision. "
                   + "Nothing gets written against an unprotected book.", ground: .ink)
            if let st = fl?.stress, let to = st.to, let drop = st.dropPct {
                // The stress price is STATED, never implied — the saved figure is
                // meaningless without knowing which fall it was measured in.
                Text("at \(f2(to)), \(Int(drop))% down".uppercased())
                    .font(PP.mono(9.5)).tracking(9.5 * 0.08)
                    .foregroundStyle(PP.dim(.ink))
                    .padding(.top, 15)
                HStack(alignment: .top, spacing: 10) {
                    pair(fl?.costLabel, "the floor costs")
                    pair(st.savedLabel, st.unhedgedLabel.map { "it saves vs \($0)" } ?? "it saves")
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(PP.hairline(.ink)).frame(height: 1) }
            }
        }
    }

    @ViewBuilder private func pair(_ value: String?, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value ?? "—").font(PP.mono(17)).monospacedDigit()
                .foregroundStyle(PP.inkText).lineLimit(1).minimumScaleFactor(0.7)
            Text(label.uppercased()).font(PP.mono(10)).tracking(10 * 0.1)
                .foregroundStyle(PP.dim(.ink)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Three points, connected. The engine computed them — this view only maps price
/// and P&L onto the box, so the drawn line cannot disagree with the figures beside
/// it. Hue appears on the loss region and nowhere else.
private struct PPFloorChart: View {
    let pay: PPPayoffLine
    let fl: PPFloor?
    let shares: Double

    // ViewBuilder closures take expressions, not declarations, so the mapping lives
    // on the struct. It is also the honest place for it: these are the only
    // calculations this page performs, and they map numbers onto a box — they do
    // not produce any.
    private var pts: [(px: Double, pl: Double)] {
        (pay.points ?? []).compactMap { p in
            guard let px = p.px, let pl = p.pl else { return nil }
            return (px, pl)
        }
    }
    private var lo: Double { pay.lo ?? pts.first?.px ?? 0 }
    private var hi: Double { pay.hi ?? pts.last?.px ?? 1 }
    private var vLo: Double { pts.map(\.pl).min() ?? -1 }
    private var vHi: Double { pts.map(\.pl).max() ?? 1 }
    private func X(_ v: Double, _ W: Double) -> Double { (v - lo) / max(hi - lo, 0.0001) * W }
    private func Y(_ v: Double, _ H: Double) -> Double { H - (v - vLo) / max(vHi - vLo, 0.0001) * H }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(grouped(fl?.covers ?? 0)) of \(grouped(shares)) shares floored".uppercased())
                Spacer()
                if let n = fl?.puts, let e = fl?.expiry {
                    Text("\(n) puts · \(e)".uppercased())
                }
            }
            .font(PP.mono(9.5)).tracking(9.5 * 0.08)
            .foregroundStyle(PP.dim(.ink))
            .lineLimit(1).minimumScaleFactor(0.75)

            GeometryReader { geo in
                ZStack {
                    // Everything below flat — the region the floor is bought for, and
                    // with the conviction discs the only colour in the app.
                    Path { p in
                        p.move(to: .init(x: 0, y: Y(0, geo.size.height)))
                        p.addLine(to: .init(x: geo.size.width, y: Y(0, geo.size.height)))
                        p.addLine(to: .init(x: geo.size.width, y: geo.size.height))
                        p.addLine(to: .init(x: 0, y: geo.size.height))
                        p.closeSubpath()
                    }.fill(PP.lossHue.opacity(0.20))

                    Path { p in
                        p.move(to: .init(x: 0, y: Y(0, geo.size.height)))
                        p.addLine(to: .init(x: geo.size.width, y: Y(0, geo.size.height)))
                    }.stroke(PP.inkText.opacity(0.30), lineWidth: 1)

                    Path { p in
                        p.move(to: .init(x: X(pay.spot ?? lo, geo.size.width), y: 0))
                        p.addLine(to: .init(x: X(pay.spot ?? lo, geo.size.width), y: geo.size.height))
                    }.stroke(PP.inkText.opacity(0.20),
                             style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                    // The position: two slopes meeting at the floor. That kink is the
                    // whole point of the page.
                    Path { p in
                        for (n, pt) in pts.enumerated() {
                            let point = CGPoint(x: X(pt.px, geo.size.width),
                                                y: Y(pt.pl, geo.size.height))
                            if n == 0 { p.move(to: point) } else { p.addLine(to: point) }
                        }
                    }.stroke(PP.inkText, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))

                    if pts.count >= 2 {
                        Circle().fill(PP.inkText).frame(width: 9, height: 9)
                            .position(x: X(pts[1].px, geo.size.width),
                                      y: Y(pts[1].pl, geo.size.height))
                    }
                    if let be = fl?.breakeven {
                        Circle().strokeBorder(PP.inkText, lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                            .position(x: X(be, geo.size.width), y: Y(0, geo.size.height))
                    }
                }
            }
            .frame(height: 124)

            HStack {
                Text("\(Int(lo)) · \(fl?.stress?.hedgedLabel ?? "—")".uppercased())
                Spacer()
                Text("floor \(Int(pay.floor ?? 0))".uppercased())
                Spacer()
                Text("breakeven \(f2(fl?.breakeven ?? 0))".uppercased())
            }
            .font(PP.mono(9.5)).tracking(9.5 * 0.08)
            .foregroundStyle(PP.dim(.ink))
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(EdgeInsets(top: 15, leading: 15, bottom: 13, trailing: 15))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(PP.inkText.opacity(0.12), lineWidth: 1))
        .padding(.top, 26)
    }
}

// MARK: - 06 · Earnings grade (ink)

/// The strip fills forward, one print at a time. Before the first print lands
/// there is no quarter to ask about — which the page says, rather than showing
/// a zero.
struct PPGradePage: View {
    let r: PPResponse
    @Binding var grade: Int

    var body: some View {
        let q = r.plan?.gradeQuarter
        PPPage(ground: .ink) {
            HStack(alignment: .firstTextBaseline) {
                PPKicker(text: "earnings grade", ground: .ink)
                Spacer()
                if let rep = q?.reported {
                    Text("reported \(Self.shortDate(rep))".uppercased())
                        .font(PP.mono(10.5)).tracking(10.5 * 0.08)
                        .foregroundStyle(PP.dim(.ink))
                }
            }
            if let label = q?.label {
                PPSay(text: "How was \(label)?", ground: .ink)
                PPFine(text: "\(q?.sessionsAgo ?? 0) sessions ago. It fades out over 60"
                       + (q?.nextPrint.map { ", and the next one opens after the \(Self.shortDate($0)) print" } ?? "")
                       + ".", ground: .ink)
            } else {
                PPSay(text: "No quarter to grade yet.", ground: .ink)
                PPFine(text: "A print becomes gradeable the morning after it lands"
                       + (q?.nextPrint.map { ". The next one is \(Self.shortDate($0))" } ?? "")
                       + ". Nothing is backfilled — a grade given months late is not the "
                       + "one you would have given at the time.", ground: .ink)
            }
        } base: {
            if q?.label != nil {
                PPNum(value: "\(grade)", unit: "of 10", ground: .ink)
                HStack(spacing: 10) {
                    PPStep(symbol: "−") { grade = max(0, grade - 1) }
                    PPStep(symbol: "+") { grade = min(10, grade + 1) }
                }
                .padding(.top, 20)
                PPGradeStrip(rows: r.plan?.gradeHistory ?? [], live: grade)
            }
        }
    }

    private static func shortDate(_ iso: String) -> String {
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "d MMM"
        return out.string(from: d)
    }
}

private struct PPStep: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(symbol).font(PP.mono(24))
                .frame(width: 60, height: 60)
                .overlay(Circle().strokeBorder(PP.inkText.opacity(0.28), lineWidth: 1))
                .foregroundStyle(PP.inkText)
        }
    }
}

/// One column per graded quarter. A null grade is "not graded", drawn as an
/// em dash with no bar — never as a zero-height bar, which would read as a 0.
private struct PPGradeStrip: View {
    let rows: [PPGradeRow]
    let live: Int
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let isNow = row.current == true
                let val = isNow ? live : row.g
                VStack(alignment: .leading, spacing: 8) {
                    Text(val.map(String.init) ?? "—")
                        .font(PP.mono(14))
                        .foregroundStyle(isNow ? PP.inkText : PP.dim(.ink))
                    GeometryReader { geo in
                        if let v = val {
                            Capsule().fill(isNow ? PP.inkText : PP.dim(.ink))
                                .frame(width: max(2, geo.size.width * Double(v) / 10),
                                       height: isNow ? 5 : 4)
                        }
                    }
                    .frame(height: 5)
                    Text((row.q ?? "").uppercased())
                        .font(PP.mono(9)).tracking(9 * 0.1)
                        .foregroundStyle(isNow ? PP.inkText : PP.dim(.ink))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(PP.hairline(.ink)).frame(height: 1) }
        .padding(.top, 24)
    }
}

// MARK: - small helpers

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
    func appendingPeriod() -> String {
        let t = trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return t }
        return t.hasSuffix(".") ? t : t + "."
    }
}

private extension Optional where Wrapped == String {
    var capitalizedFirst: String? { self?.capitalizedFirst }
}
