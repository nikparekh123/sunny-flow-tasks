//
//  IncomeScreen.swift
//  Sunnyfi — Ink · the income sleeve
//
//  Several names, ONE rule: own a block, sell an ATM call and an ATM put every
//  week, hold a long-dated OTM put as a floor. Spec: docs/INCOME_SLEEVE_SPEC.md
//
//  ── This is Claude Design's screen, replicated, not interpreted ──────────────
//  Brief: docs/INCOME_SCREEN_DESIGN_BRIEF.md. Returned 2026-08-16 as
//  ~/Downloads/income_export (Income - Ink.html + ink-income.jsx). Every measure
//  here comes from that CSS: 348pt cards, 22pt body gutter, hero at 40, band
//  labels at 12.5 with .07em tracking, the 8pt range track. Where this file and
//  the export disagree, the export is right.
//
//  The first build was mine and it was wrong twice over. It stacked the names
//  vertically because I argued a rail hides the third-ranked one; the design
//  answers that by numbering the eyebrow 01/02/03 and stating the ranking basis
//  above the rail, so the order survives being scrolled. And it was set several
//  points smaller than this throughout, which is the "too small to read"
//  Nik reported.
//
//  ── The contract ─────────────────────────────────────────────────────────────
//  EVERY DISPLAYED STRING IS EMITTED BY THE ENGINE. This file formats nothing.
//  The only number crossing the boundary is foot.pct, which sets the width of
//  the range track. Two clients formatting one figure two ways is how the
//  covered-call card ended up reading $499 against a summary saying $249.
//
//  ── Tone ─────────────────────────────────────────────────────────────────────
//  No warning state. An earlier build had CAREFUL, which fired on a missing floor
//  and printed "CAREFUL - no floor set" against a sleeve that had not opened yet.
//  Facts only: a missing floor reads "No floor yet."
//

import SwiftUI

// MARK: - the payload

struct IncomeSleeve: Decodable {
    var ok: Bool?
    var asof: String?
    var expiry: String?
    var note: String?
    var grp: String?
    var basis: String?
    var head: Head?
    var names: [Name]?
    /// The scanner: which of the 143 names are eligible, as their own rail. It is
    /// the same shapes as the sleeve — a wide head card and a rail of position
    /// cards — because it answers the same kind of question about names Nik does
    /// not hold yet.
    var scanner: Block?
    /* The opportunity view: what the book owes, and what clears the edge floor
       today. Same {head, grp, rows} anatomy as the scanner, so it renders
       through the identical card views and the client decides nothing. */
    var book: Block?

    /* A LIST, not a rail. Twelve candidates and thirteen skip reasons are a
       shortlist: read down, not swiped through. A full card per row only earns
       its space when each row is worth dwelling on, which is true of a position
       and not true of a name that failed a gate. `head` is optional because the
       book has none: Nik removed the commitment card 2026-08-18. */
    struct Block: Decodable {
        var head: Head?
        var grp: String
        var note: String?
        var list: [ListRow]
    }

    struct ListRow: Decodable {
        var n: String
        var sym: String
        var price: String
        var chip: String
        var fill: Bool?
        var fig: String
        var line: String
    }
    var error: String?

    /// A band cell. `text` renders as prose rather than a figure; `mark` underlines
    /// it. Both come from the engine — the client does not decide what is a figure.
    struct Cell: Decodable {
        var k: String
        var v: String
        var text: Bool?
        var mark: Bool?
    }

    struct Stamp: Decodable {
        var text: String
        var forecast: Bool?
    }

    struct Foot: Decodable {
        var lab: String
        var fig: String
        var sub: String
        /// The one number the client is allowed to use as a number: the track width.
        var pct: Double
        var line: String
    }

    /// The wide header card. Same anatomy as a position card, minus the foot.
    struct Head: Decodable {
        var n: String
        var sym: String
        var chip: String
        var hero: String
        var unit: String
        var bullets: [String]
        var band: [Cell]
        var stamp: String
    }

    struct Card: Decodable {
        var n: String
        var sym: String
        var price: String
        var chip: String
        var fill: Bool?
        /// Dashes the hero underline and hollows the stamp dot. It is the whole
        /// defence against a projection being read as a track record.
        var forecast: Bool?
        var hero: String
        var unit: String
        var bullets: [String]
        var earn: String
        var band: [Cell]
        var foot: Foot
        var stamp: Stamp
    }

    struct Name: Decodable, Identifiable {
        var ticker: String
        var id: String { ticker }
        var rank: Int?
        var card: Card?
    }
}

// MARK: - store

@Observable
final class IncomeStore {
    var sleeve: IncomeSleeve?
    var error: String?
    var loading = false

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        error = nil
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/income-sleeve") else {
            error = "bad url"; return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data("{}".utf8)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                error = "HTTP \(http.statusCode)"; return
            }
            let parsed = try JSONDecoder().decode(IncomeSleeve.self, from: data)
            if let e = parsed.error { error = e; return }
            sleeve = parsed
        } catch {
            self.error = String(describing: error)
        }
    }
}

// MARK: - Figure: numbers in prose go mono

/// Ink's Figure treatment, ported from the export's `Fig` component. A bullet
/// reading "Write 6 puts 350 · Fri 18 Sep for $10,200." sets the quantities in
/// mono and the words in the display face, so the numbers are scannable inside a
/// sentence. Cheap to do, and it is most of why the bullets read as data.
private func inkFig(_ s: String, size: CGFloat, color: Color) -> Text {
    var out = Text("")
    var run = ""
    var isNum = false

    func flush() {
        guard !run.isEmpty else { return }
        out = out + Text(run).font(isNum ? InkFont.mono(size) : InkFont.display(size))
        run = ""
    }
    // A character belongs to a figure if it is a digit or one of the glyphs that
    // holds a figure together. A bare "%" or "$" beside a word stays prose.
    for ch in s {
        let digit = ch.isNumber
        let glue = "$,.%–−-".contains(ch)
        let num = digit || (glue && (isNum || digit))
        if num != isNum && !(glue && !isNum) { flush(); isNum = num }
        run.append(ch)
    }
    flush()
    return out.foregroundColor(color)
}

// MARK: - the screen

struct IncomeScreen: View {
    @State private var store = IncomeStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let s = store.sleeve, let h = s.head {
                    // secthead: Newsreader 26 + the as-of stamp, per the export
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Income").font(InkFont.serif(26)).tracking(26 * -0.015)
                            .foregroundStyle(Ink.text)
                        Spacer(minLength: 0)
                        Text(dayStamp(s.asof)).font(InkFont.mono(12.5)).tracking(12.5 * 0.09)
                            .foregroundStyle(Ink.dim).fixedSize()
                    }
                    .padding(EdgeInsets(top: 24, leading: 16, bottom: 18, trailing: 16))

                    SleeveCard(h: h).padding(.horizontal, 16)

                    // grp-h: the ranking basis, and how many names carry it
                    HStack(spacing: 9) {
                        Text((s.grp ?? "").uppercased()).font(InkFont.mono(12.5))
                            .tracking(12.5 * 0.2).foregroundStyle(Ink.dim)
                        Text("\(s.names?.count ?? 0)").font(InkFont.mono(12.5))
                            .tracking(12.5 * 0.1).foregroundStyle(Ink.text)
                    }
                    // 24/18, not the export's 8/10. On device the label sat
                    // wedged between the sleeve card and the rail with no room
                    // either side; it is a section break and has to read as one.
                    .padding(EdgeInsets(top: 24, leading: 16, bottom: 18, trailing: 16))

                    // The rail. Equal-height cards, snapped, in rank order.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(ranked(s.names ?? [])) { n in
                                if let c = n.card { PosCard(c: c) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                        .padding(.bottom, 8)
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollClipDisabled()

                    /* THE BOOK, above the scanner on purpose. The scanner is a
                       shortlist of names that might one day be worth owning; this
                       is what to do today. The thing you act on goes first. */
                    if let bk = s.book {
                        GrpHead(label: bk.grp, count: bk.list.count)
                        ListCard(note: bk.note, rows: bk.list)
                            .padding(.horizontal, 16)
                    }

                    if let sc = s.scanner {
                        if let h = sc.head {
                            SleeveCard(h: h).padding(.horizontal, 16).padding(.top, 26)
                        }
                        GrpHead(label: sc.grp, count: sc.list.count)
                        ListCard(note: sc.note, rows: sc.list)
                            .padding(.horizontal, 16)
                    }

                    if let note = s.note { NoteFoot(text: note) }
                } else if let e = store.error {
                    Quiet(title: "Could not load", body: e)
                } else {
                    Quiet(title: "Loading", body: "Reading the sleeve.")
                }
                Color.clear.frame(height: 96)
            }
            /* LOCKED to the container, not to .infinity.

               maxWidth: .infinity only says "take everything offered"; it does
               not stop a child whose MINIMUM width exceeds the screen from
               widening the whole stack. When that happens every full-width card
               grows with it and the page sits wider than the display, centred,
               so it clips at both edges at once: the "Income" title loses its I
               and the date loses its G, and the page drifts sideways.

               containerRelativeFrame pins the width to the scroll view's own
               width, so an over-wide child clips inside its own card instead of
               dragging the page with it. The horizontal rail below is a
               ScrollView and manages its own content, so it is unaffected. */
            .containerRelativeFrame(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { if store.sleeve == nil { await store.load() } }
        .refreshable { await store.load() }
    }

    /// Rank order. An unranked row (one that failed to price) sinks to the end
    /// rather than being dropped: a name that could not be priced is still held.
    private func ranked(_ ns: [IncomeSleeve.Name]) -> [IncomeSleeve.Name] {
        ns.sorted { ($0.rank ?? 99) < ($1.rank ?? 99) }
    }

    /// The one string the engine does not emit, because it is chrome rather than
    /// content: the section-head as-of. "2026-08-16" -> "SUN 16 AUG".
    private func dayStamp(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        guard let d = f.date(from: String(iso.prefix(10))) else { return "" }
        let o = DateFormatter(); o.dateFormat = "EEE d MMM"; o.timeZone = f.timeZone
        return o.string(from: d).uppercased()
    }
}

// MARK: - card parts, each one measured off the export's CSS

private enum IC {
    static let cardW: CGFloat = 348
    /// Every position card is this tall so the rail stays level. The body's
    /// spacer absorbs the slack; content longer than this CLIPS, silently, off
    /// the bottom — the same failure the InkCard header documents.
    ///
    /// 720, measured rather than guessed. At 660 the ranked-first card fitted
    /// exactly and looked fine, and the SKIPPED card lost half its stamp: it
    /// carries a two-line skip bullet AND a wrapped earnings line ("Thu 25 Sep ·
    /// 12 days · inside this expiry"). Roughly one card in five is a skip, so the
    /// worst case is the normal case. Anything added to the body must be checked
    /// against a skipped row, not a writing one.
    static let cardH: CGFloat = 720
    static let gutter: CGFloat = 22
}

private struct Eyebrow: View {
    let n: String, sym: String, price: String?, chip: String, fill: Bool
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(n.uppercased()).font(InkFont.mono(12.5)).tracking(12.5 * 0.16).foregroundStyle(Ink.dim)
                sep
                Text(sym.uppercased()).font(InkFont.mono(12.5)).tracking(12.5 * 0.16)
                    .foregroundStyle(Ink.text)
                if let price, !price.isEmpty {
                    sep
                    Text(price).font(InkFont.mono(13.5)).foregroundStyle(Ink.dim)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Text(chip.uppercased()).font(InkFont.mono(12.5)).tracking(12.5 * 0.05)
                .foregroundStyle(fill ? Ink.invertText : Ink.text)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(fill ? Ink.invertBg : .clear))
                .overlay(Capsule().strokeBorder(fill ? .clear : Ink.text, lineWidth: 1))
                .fixedSize()
        }
        .frame(minHeight: 30)
    }
    private var sep: some View {
        Text("·").font(InkFont.mono(12.5)).foregroundStyle(Ink.dim).opacity(0.7)
    }
}

private struct Hero: View {
    let fig: String, unit: String, forecast: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(fig).font(InkFont.mono(40, .medium)).tracking(40 * -0.04)
                .foregroundStyle(Ink.text)
                .padding(.bottom, forecast ? 7 : 0)
                // A forecast wears a dashed rule. It is the difference between
                // "this is what it has done" and "this is what it would pay".
                .overlay(alignment: .bottom) {
                    if forecast {
                        Line().stroke(Ink.dim, style: .init(lineWidth: 1, dash: [3, 3]))
                            .frame(height: 1)
                    }
                }
                .fixedSize()
            Text(unit.uppercased()).font(InkFont.mono(12.5)).tracking(12.5 * 0.05)
                .foregroundStyle(Ink.dim).lineSpacing(4).padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 26)
    }
    private struct Line: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path(); p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: r.width, y: 0)); return p
        }
    }
}

private struct Bullets: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(items, id: \.self) { t in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Ink.dim).frame(width: 4, height: 4).offset(y: -4)
                    inkFig(t, size: 15, color: Ink.text)
                        .lineSpacing(15 * 0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 22)
    }
}

private struct Band: View {
    let items: [IncomeSleeve.Cell]
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let b = items[i]
                VStack(alignment: .leading, spacing: 11) {
                    Text(b.k.uppercased()).font(InkFont.mono(12.5)).tracking(12.5 * 0.07)
                        .foregroundStyle(Ink.dim).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Group {
                        if b.text == true {
                            Text(b.v).font(InkFont.display(15)).foregroundStyle(Ink.text)
                        } else {
                            Text(b.v).font(InkFont.mono(17)).tracking(17 * -0.02)
                                .foregroundStyle(Ink.text).lineLimit(1)
                        }
                    }
                    // `mark` underlines the figure the card wants read first. On a
                    // position card that is Commits: what assignment would cost.
                    .padding(.bottom, b.mark == true ? 3 : 0)
                    .overlay(alignment: .bottom) {
                        if b.mark == true { Rectangle().fill(Ink.text).frame(height: 1.5) }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, i == 0 ? 0 : 10).padding(.trailing, 10).padding(.top, 18)
                .overlay(alignment: .leading) {
                    if i > 0 { Rectangle().fill(Ink.hair).frame(width: 1) }
                }
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }
}

/// The foot, and the one graphic on the screen: where the price sits in its year.
private struct FootZone: View {
    let f: IncomeSleeve.Foot
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(f.lab.uppercased()).font(InkFont.mono(12.5)).tracking(12.5 * 0.07)
                .foregroundStyle(Ink.dim)
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text(f.fig).font(InkFont.mono(26)).tracking(26 * -0.03).foregroundStyle(Ink.text)
                Text(f.sub).font(InkFont.display(13.5)).foregroundStyle(Ink.dim)
            }
            GeometryReader { g in
                let x = g.size.width * CGFloat(max(0, min(100, f.pct)) / 100)
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.hair).frame(height: 8)
                    Capsule().fill(Ink.text).opacity(0.88).frame(width: x, height: 8)
                    Rectangle().fill(Ink.text).frame(width: 2, height: 16).offset(x: x - 1)
                }
                .frame(height: 16, alignment: .center)
            }
            .frame(height: 16)
            inkFig(f.line, size: 13.5, color: Ink.dim)
                .lineSpacing(13.5 * 0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 18, leading: IC.gutter, bottom: 20, trailing: IC.gutter))
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }
}

/// The freshness stamp, INSIDE the card under a hairline. A hollow dot means the
/// figure above it is a forecast, not a reading.
private struct CardStamp: View {
    let text: String, forecast: Bool
    var body: some View {
        HStack(spacing: 9) {
            Group {
                if forecast {
                    Circle().strokeBorder(Ink.dim, lineWidth: 1.5)
                } else {
                    Circle().fill(Ink.text)
                }
            }
            .frame(width: 6, height: 6)
            Text(text.uppercased()).font(InkFont.mono(12.5)).tracking(12.5 * 0.06)
                .foregroundStyle(Ink.dim)
            Spacer(minLength: 0)
        }
        .opacity(0.85)
        .padding(EdgeInsets(top: 14, leading: IC.gutter, bottom: 15, trailing: IC.gutter))
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }
}

// MARK: - the two cards

private struct PosCard: View {
    let c: IncomeSleeve.Card
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(n: c.n, sym: c.sym, price: c.price, chip: c.chip, fill: c.fill ?? false)
                Hero(fig: c.hero, unit: c.unit, forecast: c.forecast ?? false)
                Bullets(items: c.bullets)
                Spacer(minLength: 26)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Next earnings".uppercased()).font(InkFont.mono(12.5))
                        .tracking(12.5 * 0.07).foregroundStyle(Ink.dim)
                    Spacer(minLength: 0)
                    inkFig(c.earn, size: 15, color: Ink.text)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 17)
                Band(items: c.band)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(EdgeInsets(top: IC.gutter, leading: IC.gutter,
                                bottom: 24, trailing: IC.gutter))
            FootZone(f: c.foot)
            CardStamp(text: c.stamp.text, forecast: c.stamp.forecast ?? false)
        }
        .frame(width: IC.cardW, height: IC.cardH, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
            .fill(Ink.surface))
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous))
    }
}

/// The wide header. Same anatomy, full width, no foot: what is collectable this
/// week, how the money is split across the names, and whether the floors have
/// paid for themselves.
private struct SleeveCard: View {
    let h: IncomeSleeve.Head
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(n: h.n, sym: h.sym, price: nil, chip: h.chip, fill: false)
                Hero(fig: h.hero, unit: h.unit, forecast: false)
                Bullets(items: h.bullets)
                Spacer(minLength: 26)
                Band(items: h.band)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(EdgeInsets(top: IC.gutter, leading: IC.gutter,
                                bottom: 24, trailing: IC.gutter))
            CardStamp(text: h.stamp, forecast: false)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
            .fill(Ink.surface))
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous))
    }
}

// MARK: - the list card

/// The section break above a card or rail.
private struct GrpHead: View {
    let label: String; let count: Int
    var body: some View {
        HStack(spacing: 9) {
            Text(label.uppercased()).font(InkFont.mono(12.5))
                .tracking(12.5 * 0.2).foregroundStyle(Ink.dim)
            Text("\(count)").font(InkFont.mono(12.5))
                .tracking(12.5 * 0.1).foregroundStyle(Ink.text)
        }
        .padding(EdgeInsets(top: 24, leading: 16, bottom: 18, trailing: 16))
    }
}

/// One card, many rows. Each row is two lines: the identity and the figure on
/// the first, the reason on the second. Hairlines between, none at the ends.
private struct ListCard: View {
    let note: String?
    let rows: [IncomeSleeve.ListRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let note, !note.isEmpty {
                inkFig(note, size: 13.5, color: Ink.dim)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 18, leading: IC.gutter,
                                        bottom: 16, trailing: IC.gutter))
            }
            ForEach(rows.indices, id: \.self) { i in
                if i > 0 || note != nil {
                    Rectangle().fill(Ink.hair).frame(height: 1)
                }
                row(rows[i])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous)
            .fill(Ink.surface))
        .clipShape(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous))
    }

    private func row(_ r: IncomeSleeve.ListRow) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text(r.n).font(InkFont.mono(12.5)).tracking(12.5 * 0.16)
                    .foregroundStyle(Ink.dim)
                Text(r.sym.uppercased()).font(InkFont.mono(13.5)).tracking(13.5 * 0.08)
                    .foregroundStyle(Ink.text).layoutPriority(2)
                Text(r.price).font(InkFont.mono(12.5)).foregroundStyle(Ink.dim)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                // Shrinks rather than pushes. A five-character figure never
                // needs this; a name at $1,234.56 with a wide chip beside it
                // would, and the row must give before the page does.
                Text(r.fig).font(InkFont.mono(19)).tracking(19 * -0.03)
                    .foregroundStyle(Ink.text).lineLimit(1)
                    .minimumScaleFactor(0.7).layoutPriority(3)
                Text(r.chip.uppercased()).font(InkFont.mono(11)).tracking(11 * 0.05)
                    .foregroundStyle((r.fill ?? false) ? Ink.invertText : Ink.dim)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill((r.fill ?? false) ? Ink.invertBg : .clear))
                    .overlay(Capsule().strokeBorder(
                        (r.fill ?? false) ? .clear : Ink.hair, lineWidth: 1))
                    .fixedSize()
            }
            .lineLimit(1)
            inkFig(r.line, size: 13.5, color: Ink.dim)
                .lineSpacing(13.5 * 0.35)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 16, leading: IC.gutter, bottom: 16, trailing: IC.gutter))
    }
}

// MARK: - footer + quiet states

/// A note, not a total. The blocks here are the tool, not the holding, and a
/// screen that ends on a big premium figure quietly says the opposite.
private struct NoteFoot: View {
    let text: String
    var body: some View {
        Text(text)
            .font(InkFont.display(13.5))
            .foregroundStyle(Ink.dim)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 18)
    }
}

private struct Quiet: View {
    let title: String; let body_: String
    init(title: String, body: String) { self.title = title; self.body_ = body }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(InkFont.serif(26)).foregroundStyle(Ink.text)
            Text(body_).font(InkFont.display(15)).foregroundStyle(Ink.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 60)
    }
}
