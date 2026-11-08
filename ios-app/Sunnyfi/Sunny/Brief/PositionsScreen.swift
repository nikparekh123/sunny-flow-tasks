//
//  PositionsScreen.swift
//  Sunny
//
//  Positions, one name at a time (block 31, Search Explorations 47a): the account strip (scrolls away), the
//  large title, the book's totals in one sideways row (a tap cycles time value, % change, $ change), the logo
//  strip (an orange dot = short at its priced move by Friday), the name row, then the chart card edge to edge
//  (P&L and its status, the Greeks, the payoff on the date picked, drag to set the price, the date slider),
//  Walls or Technicals, the legs (tap one to switch it off), the summary line, the fixes when short, Walls by
//  expiry, and the whole book in that name. Nothing pins except the nav bar.
//

import SwiftUI

struct BriefPositionsScreen: View {
    @Environment(BriefState.self) private var brief
    @Environment(HomeRouter.self) private var router
    @AppStorage(BriefPrivacy.key) private var privacy = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    @State private var name: String = BriefDebug.name ?? (BriefDebug.sample ? "NKE" : "")
    @State private var stop = BriefDebug.stop ?? 0
    @State private var pos = ScrollPosition()
    @State private var price: Double?
    @State private var off: Set<String> = []
    @State private var legFilter = "All"
    @State private var layer: String? = "Walls"
    @State private var fix: String?
    @State private var totalsMode = 0
    @State private var wallsKind = "All"

    private var acct: String { brief.account.sampleKey }
    private var weekend: Bool { brief.moment() == .weekend }
    @State private var chain = 0
    @State private var scrolled: CGFloat = 0
    /// Counts the logo picks a finger makes, for the selection haptic (a name set by the app makes none).
    @State private var logoPicks = 0
    /// The account switch, as Home does it: the page at 15% (`faded`) and 28 pt toward the new account (`slid`),
    /// then back on S.switchFade and S.switchMove.
    @State private var faded = false
    @State private var slid = false
    @State private var dipDir: CGFloat = 0
    @State private var settling: Task<Void, Never>?
    /// The book the page shows (Overview keeps the last one), and whether its numbers are in: the sample books
    /// swap at once, a real one once its brief has landed (the same test as Home).
    private var pageBook: BriefAccount { brief.account == .overview ? brief.lastBook : brief.account }
    private var pageReady: Bool { BriefDebug.sample || brief.book == nil || brief.book == (pageBook == .nicolay ? "N" : "S") }

    /// Sample mode: the design's book. Otherwise the server's brief for the book on screen.
    private var live: Bool { !BriefDebug.sample }
    private var liveNames: [JSONValue] { brief.live?.names ?? [] }
    private var names: [String] {
        live ? liveNames.compactMap { $0["t"].string } : SampleBook.names.filter { SampleBook.book(acct)[$0] != nil }
    }
    private var model: PositionsModel? {
        if !live { return PositionsModel(t: name, acct: acct, weekend: weekend) }
        guard let b = brief.book else { return nil }
        return brief.positions.model(b, name)
    }
    private var totals: [PositionsModel.Holdings] {
        live ? liveNames.map(PositionsModel.holdings(json:)) : SampleBook.names.compactMap { PositionsModel(t: $0, acct: acct, weekend: weekend)?.holdings() }
    }
    private var strip: [LogoStrip.Item] {
        live ? liveNames.map { LogoStrip.Item(t: $0["t"].string ?? "", company: $0["name"].string ?? "", warn: $0["short"].bool) }
            : names.map { LogoStrip.Item(t: $0, company: SampleBook.company[$0] ?? $0, warn: PositionsModel(t: $0, acct: acct, weekend: weekend)?.shortByFriday ?? false) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if brief.showsStrip {
                    // The new book swaps in at once; the dip below is the motion (block 33).
                    AccountStrip(accounts: brief.accounts, selected: brief.account) { a in brief.pick(a) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Positions").sType(SType(size: 34, weight: 800, line: 40, tracking: -0.02), tabular: false)
                        .foregroundStyle(S.ink).padding(.horizontal, S.margin).padding(.top, brief.showsStrip ? 4 : 16)
                        .accessibilityAddTraits(.isHeader)
                    if live && names.isEmpty {
                        // An empty book (Nicolay's, until he trades): one line, as agreed.
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nothing held yet").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            Text("Each name you hold shows here once IBKR reports it.").sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
                        }
                        .padding(.horizontal, S.margin).padding(.top, 16)
                    }
                    if !names.isEmpty {
                        BookTotalsRow(hs: totals, mode: $totalsMode, privacy: privacy).padding(.top, 12)
                        LogoStrip(items: strip, selected: name) { t in
                            if t != name { logoPicks += 1 }
                            withAnimation(S.fade) { name = t; price = nil; off = []; fix = nil }
                        }
                        .padding(.top, 16)
                        .sensoryFeedback(.selection, trigger: logoPicks)
                    }
                    if let m = model {
                        NameRow(m: m).padding(.horizontal, S.margin).padding(.top, 14)
                        if live, let t = brief.asOf() {
                            Text("As of \(Self.asOfWords(t)) · IBKR data is late").sType(BK.sub, tabular: false).foregroundStyle(S.act)
                                .padding(.horizontal, S.margin).padding(.top, 4)
                        }
                        // In a ZStack so a new name crossfades in place (S.fade) instead of stacking under the old one.
                        ZStack(alignment: .topLeading) {
                            PositionsDetail(m: m, stop: Binding(get: { min(stop, m.stops.count - 1) }, set: { stop = $0 }), price: $price, off: $off,
                                            legFilter: $legFilter, layer: $layer, chain: $chain, fix: $fix, wallsKind: $wallsKind, privacy: privacy,
                                            late: live && brief.asOf() != nil)
                                .id("\(acct)-\(name)")
                        }
                        .padding(.top, 12)
                    } else if live && !names.isEmpty, let b = brief.book {
                        Group {
                            if let e = brief.positions.error(b, name) { Text(e) } else { ProgressView().controlSize(.regular) }
                        }
                        .sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                // The account switch (README 11.4, block 33): this one page under the strip, never a second copy,
                // jumps to 15% and 28 pt toward the new account, then settles (S.switchFade 0.4 s, S.switchMove 0.5 s).
                // Every figure swaps at once, under the dip. Reduce Motion: the fade only.
                .opacity(faded ? 0.15 : 1)
                .offset(x: slid ? 28 * dipDir : 0)
            }
            .padding(.bottom, 128)
            .containerRelativeFrame(.horizontal)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($pos)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, v in scrolled = v }
        .task {
            if let y = BriefDebug.scroll { try? await Task.sleep(for: .milliseconds(600)); pos.scrollTo(y: y) }
        }
        .background(SBackground(glows: false))
        .overlay(alignment: .top) { BriefTopEdge() }
        // The nav bar's small title once the large one has scrolled under it (block 31): "NKE Positions".
        .overlay(alignment: .top) {
            let shown = scrolled > (brief.showsStrip ? 110 : 40)
            Text("\(name) Positions").sFont(17, .semibold).foregroundStyle(S.ink)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(alignment: .bottom) { Rectangle().fill(.bar).ignoresSafeArea(edges: .top).frame(height: 120, alignment: .bottom) }
                .overlay(alignment: .bottom) { Rectangle().fill(S.hairline).frame(height: 0.5) }
                .opacity(shown ? 1 : 0)
                .animation(S.fade, value: shown)
                .allowsHitTesting(false)
                // Out of VoiceOver while it is invisible.
                .accessibilityHidden(!shown)
        }
        .onAppear(perform: arrive)
        .onChange(of: brief.positionsName) { _, _ in arrive() }
        .onChange(of: names) { _, _ in arrive() }
        .onChange(of: name) { _, t in if live, !t.isEmpty, let b = brief.book { UserDefaults.standard.set(t, forKey: "positions.last.\(b)") }; load() }
        .onChange(of: brief.built) { _, _ in load() }
        .onChange(of: model?.stops.count) { _, _ in arriveAtFriday() }
        .onChange(of: pageBook) { _, _ in dip() }
        .onChange(of: pageReady) { _, ready in if ready && faded { settle(wait: false) } }
    }

    /// The switch's first frame, drawn with no animation: 15%, and 28 pt toward the new account (not under
    /// Reduce Motion). Runs in the same update as the swap, so the new figures never show at full strength first.
    private func dip() {
        guard brief.showsStrip else { return }
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { dipDir = brief.switchDir; faded = true; slid = !reduce }
        settle(wait: !pageReady)
    }
    /// Back to full and home two frames after the dip has drawn; a real book still loading holds the dip until
    /// its brief lands, 1.5 s at most.
    private func settle(wait: Bool) {
        settling?.cancel()
        settling = Task {
            try? await Task.sleep(for: .milliseconds(wait ? 1500 : 34))
            guard !Task.isCancelled else { return }
            withAnimation(S.switchFade) { faded = false }
            withAnimation(S.moving(S.switchMove, reduce)) { slid = false }
        }
    }

    /// "3:58 PM" today, "Fri 3:58 PM" before today.
    static func asOfWords(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = Calendar.current.isDate(d, inSameDayAs: SClock.now()) ? "h:mm a" : "EEE h:mm a"
        return f.string(from: d)
    }

    /// From a Your position row: that name at the Friday close stop. From the tab: the last name viewed, or on
    /// the first open the first name past its best by Friday, else the biggest (answer 4).
    private func arrive() {
        if let t = brief.positionsName, names.contains(t) { name = t; brief.positionsName = nil }
        if live, !names.contains(name) {
            let last = brief.book.flatMap { UserDefaults.standard.string(forKey: "positions.last.\($0)") }
            if let l = last, names.contains(l) { name = l }
            else if let s = liveNames.first(where: { $0["short"].bool })?["t"].string { name = s }
            else { name = liveNames.max { ($0["size"].double ?? 0) < ($1["size"].double ?? 0) }?["t"].string ?? names.first ?? "" }
        }
        load()
        arriveAtFriday()
    }
    private func arriveAtFriday() {
        guard brief.positionsAtFriday, let m = model else { return }
        stop = m.fridayStop; price = nil; brief.positionsAtFriday = false
    }
    /// Live: ask for the name on screen when it is missing or priced on an older build.
    private func load() {
        guard live, !name.isEmpty, let b = brief.book, let built = brief.built,
              let n = liveNames.first(where: { $0["t"].string == name }) else { return }
        brief.positions.load(book: b, t: name, built: built, name: n)
    }
}

/// VoiceOver words for this screen (Pass 5): signs as words, no glyphs, book money "hidden" with privacy on.
/// Prices and percentages stay.
private enum PosSay {
    /// A price: "35 dollars 28".
    static func price(_ p: Double) -> String {
        let c = Int((abs(p) * 100).rounded()), d = c / 100, r = c % 100
        return r == 0 ? "\(d) dollars" : "\(d) dollars \(String(format: "%02d", r))"
    }
    /// Book money in full: "3,686 dollars", or "hidden".
    static func money(_ v: Double, _ privacy: Bool) -> String { privacy ? "hidden" : "\(SampleEngine.fn(v)) dollars" }
    /// Book money as the stats write it ($12K, $1.2K): "12 thousand dollars", or "hidden".
    static func moneyK(_ v: Double, _ privacy: Bool) -> String {
        if privacy { return "hidden" }
        let a = abs(v)
        if a >= 1e4 { return "\(Int((a / 1000).rounded())) thousand dollars" }
        if a >= 1000 { return String(format: "%.1f", a / 1000) + " thousand dollars" }
        return "\(Int(a.rounded())) dollars"
    }
    /// "up 3,686 dollars" or "down 3,686 dollars"; "hidden" with privacy on (the sign there is only a colour).
    static func signed(_ v: Double, _ privacy: Bool, k: Bool = false) -> String {
        privacy ? "hidden" : "\(v < 0 ? "down" : "up") \(k ? moneyK(v, false) : money(v, false))"
    }
    /// Delta or gamma as a side: "long 5,934", "short 917".
    static func side(_ v: Double) -> String { "\(v < 0 ? "short" : "long") \(SampleEngine.fn(v))" }

    private static let full: [String: String] = [
        "Jan": "January", "Feb": "February", "Mar": "March", "Apr": "April", "Jun": "June", "Jul": "July", "Aug": "August",
        "Sep": "September", "Oct": "October", "Nov": "November", "Dec": "December",
        "Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday", "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday"]
    private static let shortRE = try! NSRegularExpression(pattern: #"\b(Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b"#)
    private static let yearRE = try! NSRegularExpression(pattern: #"[’'](\d{2})\b"#)

    /// Words on screen as VoiceOver should say them: BriefWords.speech (hidden, up, down, delta, percent), plus
    /// "×" as "times", "’27" as "2027", and short months and days in full ("Calls 36 times 72, October 30").
    static func words(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "×", with: " times ")
        t = yearRE.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "20$1")
        let ns = t as NSString
        for m in shortRE.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
            if let r = Range(m.range, in: t), let w = full[ns.substring(with: m.range)] { t.replaceSubrange(r, with: w) }
        }
        return BriefWords.speech(t)
    }
}

// MARK: - Book totals (one sideways row)

private struct BookTotalsRow: View {
    let hs: [PositionsModel.Holdings]
    @Binding var mode: Int
    let privacy: Bool
    var body: some View {
        let gain = hs.reduce(0) { $0 + $1.shareGain }, tl = hs.reduce(0) { $0 + $1.timeLeaps }, to = hs.reduce(0) { $0 + $1.timeOtm }
        let ip = hs.reduce(0) { $0 + $1.ip.value }, sc = hs.reduce(0) { $0 + $1.sc.value }, sp = hs.reduce(0) { $0 + $1.sp.value }
        let shT = hs.reduce(0) { $0 + $1.sh.today }, lpT = hs.reduce(0) { $0 + $1.lp.today }, ocT = hs.reduce(0) { $0 + $1.oc.today }, ipT = hs.reduce(0) { $0 + $1.ip.today }
        let shV = hs.reduce(0) { $0 + $1.sh.value }, lpV = hs.reduce(0) { $0 + $1.lp.value }, ocV = hs.reduce(0) { $0 + $1.oc.value }
        let views = ["time value", "% today", "$ today"]
        let said = ["time value", "percent change today", "dollar change today"]
        let longItems: [(String, Double, Double, Double)] = [("Shares", gain, shT, shV), ("LEAPS", tl, lpT, lpV), ("OTM calls", to, ocT, ocV), ("Insurance puts", ip, ipT, ip)]
        // What each Long figure shows in this view: the name and the value.
        let shown: [(name: String, v: Double)] = longItems.filter { $0.1 != 0 || $0.2 != 0 }.map { it in
            (it.0, mode == 0 ? it.1 : mode == 1 ? (it.3 != 0 ? it.2 / it.3 * 100 : 0) : it.2)
        }
        let sold: [(String, Double, Bool)] = [("Calls", sc, false), ("Puts", sp, false)].filter { $0.1 != 0 }
        Button { withAnimation(S.fade) { mode = (mode + 1) % 3 } } label: {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    group("Long", shown.map { it in
                        let lbl = mode == 0 ? (it.name == "Shares" ? "Shares · gain" : it.name == "Insurance puts" ? "Insurance puts" : "\(it.name) · time value") : "\(it.name) · \(views[mode])"
                        return (lbl, it.v, mode == 1)
                    })
                    Rectangle().fill(S.hairline).frame(width: 0.5, height: 56).padding(.top, 20)
                    group("Sold · left to earn", sold)
                }
                .padding(.horizontal, S.margin)
            }
            .scrollIndicators(.hidden)
        }
        .buttonStyle(.plain)
        // VoiceOver: the view on screen, then every figure with its sign as a word (money "hidden" with privacy on).
        .accessibilityLabel("Book totals, \(said[mode])")
        .accessibilityValue(spoken(shown, sold))
        .accessibilityHint("Shows \(said[(mode + 1) % 3]) next")
    }

    private func spoken(_ long: [(name: String, v: Double)], _ sold: [(String, Double, Bool)]) -> String {
        let l = long.map { it -> String in
            let what = mode == 0 ? (it.name == "Shares" ? "Shares gain" : it.name == "Insurance puts" ? "Insurance puts" : "\(it.name) time value") : it.name
            let amount = mode == 1 ? "\(it.v < 0 ? "down" : "up") \(String(format: "%.1f", abs(it.v))) percent"
                : mode == 2 ? PosSay.signed(it.v, privacy, k: true)
                : (it.v < 0 && !privacy ? "down " : "") + PosSay.moneyK(it.v, privacy)
            return "\(what), \(amount)"
        }
        let s = sold.map { "\($0.0), \(PosSay.moneyK($0.1, privacy))" }
        var parts: [String] = []
        if !l.isEmpty { parts.append("Long. " + l.joined(separator: "; ")) }
        if !s.isEmpty { parts.append("Sold, left to earn. " + s.joined(separator: "; ")) }
        return parts.joined(separator: ". ")
    }

    private func group(_ h: String, _ items: [(String, Double, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(h).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                    if i > 0 { Rectangle().fill(S.hairline).frame(width: 0.5, height: 44) }
                    VStack(alignment: .leading, spacing: 2) {
                        BriefWords.line(it.2 ? String(format: "%.1f%%", abs(it.1)) : SampleEngine.fK(it.1), privacy: privacy)
                            .sType(SType(size: 22, weight: 800, line: 26, tracking: -0.01))
                            .foregroundStyle(it.1 < 0 ? S.red : S.ink)
                        Text(it.0).sType(SType(size: 12, weight: 500, line: 15, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Logo strip

private struct LogoStrip: View {
    struct Item: Hashable { let t: String; let company: String; let warn: Bool }
    let items: [Item]
    let selected: String
    let pick: (String) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(items, id: \.t) { it in
                    let t = it.t, on = t == selected, warn = it.warn
                    Button { pick(t) } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                BLogo(ticker: t, size: 46)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(on ? S.ink : .clear, lineWidth: 2))
                                if warn {
                                    Circle().fill(S.act).frame(width: 11, height: 11)
                                        .overlay(Circle().strokeBorder(S.sheetFill, lineWidth: 2)).offset(x: -1, y: 1)
                                }
                            }
                            Text(t).sFont(11, on ? .bold : .semibold).foregroundStyle(on ? S.ink : S.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(it.company + (warn ? ", past its best if it rises its priced move by Friday" : ""))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, S.margin)
        }
        .scrollIndicators(.hidden)
    }
}

private struct NameRow: View {
    let m: PositionsModel
    var body: some View {
        let mv = (m.S0 - m.P0) / m.P0 * 100
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(m.t).sFont(17, .bold).foregroundStyle(S.ink)
            Text(String(format: "%.2f", m.S0)).sFont(17, .medium, mono: true).foregroundStyle(S.secondary)
            Text("\(mv < 0 ? "▼" : "▲") \(String(format: "%.1f", abs(mv)))%").sFont(13, .semibold, mono: true).foregroundStyle(mv < 0 ? S.red : S.green)
            Spacer()
            if !m.strategy.isEmpty { Text(m.strategy).sFont(13, .medium).foregroundStyle(S.secondary) }
        }
        // One element: "Nike, 35 dollars 28, up 3.1 percent" (no arrow read).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.company), \(PosSay.price(m.S0)), \(mv < 0 ? "down" : "up") \(String(format: "%.1f", abs(mv))) percent"
                            + (m.strategy.isEmpty ? "" : ", \(m.strategy)"))
    }
}

// MARK: - The chart card and everything under it

private struct PositionsDetail: View {
    let m: PositionsModel
    @Binding var stop: Int
    @Binding var price: Double?
    @Binding var off: Set<String>
    @Binding var legFilter: String
    @Binding var layer: String?
    @Binding var chain: Int
    @Binding var fix: String?
    @Binding var wallsKind: String
    let privacy: Bool
    /// IBKR is late (README 9.4): the last values stay, the makes-the-most line goes.
    var late = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let st = m.stops[stop], px = price ?? m.S0, tt = st.tt
        let pl = m.pl(px, tt, off: off), g = m.greeks(px, tt, off: off), fl = late ? nil : m.flip(tt, off: off)
        let short = g.d < 0
        let fixes = m.fixes(px, tt, off: off)
        let picked = fixes.first { $0.id == fix }
        VStack(alignment: .leading, spacing: 0) {
            // The chart card, edge to edge on its own fill.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text("\(pl < 0 ? "Down" : "Up") \(BriefWords.plain("$" + SampleEngine.fn(pl), privacy: privacy))")
                        .sType(SType(size: 28, weight: 800, line: 32, tracking: -0.02))
                        .foregroundStyle(pl < 0 ? S.red : S.green)
                        .accessibilityLabel(privacy ? "\(pl < 0 ? "Down" : "Up"), hidden" : "\(pl < 0 ? "Down" : "Up") \(PosSay.money(pl, false))")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(pl < 0 ? (short ? "Losing, and rises cost you" : "Losing") : short ? "Making, past its best" : "Long and making")
                            .sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false)
                            .foregroundStyle(pl < 0 ? S.red : short ? S.act : S.green)
                        Text("\(m.t) at $\(String(format: "%.2f", px)) · \(st.long)").sType(BK.caption).foregroundStyle(S.secondary)
                            .accessibilityLabel("\(m.company) at \(PosSay.price(px)), \(PosSay.words(st.long))")
                    }
                }
                HStack(alignment: .top) {
                    greek("Delta", SampleEngine.fn(g.d), g.d < 0 ? S.red : S.ink, said: PosSay.side(g.d))
                    greek("Theta", BriefWords.plain("$" + SampleEngine.fn(g.th), privacy: privacy), g.th < 0 ? S.red : S.green, said: PosSay.signed(g.th, privacy))
                    greek("Gamma", SampleEngine.fn(g.g), g.g < 0 ? S.red : S.ink, said: PosSay.side(g.g))
                    greek("Vega", BriefWords.plain("$" + SampleEngine.fn(g.vg), privacy: privacy), g.vg < 0 ? S.red : S.ink, said: PosSay.signed(g.vg, privacy))
                }
                PositionsChart(m: m, tt: tt, price: $price, off: off, flip: fl, extra: picked?.extra ?? [], layer: layer, chain: chain,
                               phrase: st.phrase, privacy: privacy)
                    .frame(height: 190 + 40)
                DateSlider(m: m, stop: $stop)
            }
            .padding(.horizontal, S.margin)
            .padding(.vertical, 18)
            .background(S.sheetFill)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(["Walls", "Technicals"], id: \.self) { l in
                        // Lines and labels come and go and the chain chips push the page down: moving, so instant under Reduce Motion.
                        Button { withAnimation(S.moving(S.fade, reduce)) { layer = layer == l ? nil : l } } label: {
                            Text(l).sFont(14, .semibold).foregroundStyle(layer == l ? S.sheetFill : S.ink)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(Capsule().fill(layer == l ? S.ink : S.chip))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(layer == l ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: layer)
                if layer == "Walls" && chainChips.isEmpty {
                    Text("No walls saved for \(m.t) yet").sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
                } else if layer == "Walls" {
                    HStack(spacing: 8) {
                        ForEach(chainChips, id: \.0) { c in
                            Button { withAnimation(S.moving(S.spring, reduce)) { chain = c.0 } } label: {
                                Text(c.1).sFont(13, .semibold).foregroundStyle(S.ink)
                                    .padding(.horizontal, 12).frame(height: 30)
                                    .background(Capsule().fill(chain == c.0 ? S.chip : .clear))
                                    .overlay(Capsule().strokeBorder(S.hairline, lineWidth: chain == c.0 ? 0 : 1))
                            }.buttonStyle(.plain)
                            .accessibilityLabel(PosSay.words(c.1))
                            .accessibilityAddTraits(chain == c.0 ? .isSelected : [])
                        }
                    }
                    .sensoryFeedback(.selection, trigger: chain)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        legend("—", "P&L on that date", S.ink); legend("--", "Today", S.secondary)
                        legend("|", "Makes the most", S.act); legend("|", "Hurting", S.red)
                    }
                    Text("Tap a leg to switch it off").sType(BK.label, tabular: false).foregroundStyle(S.secondary)
                }
                BHairline()
                LegsList(m: m, px: px, tt: tt, off: $off, filter: $legFilter, privacy: privacy)
                BHairline()
                VStack(alignment: .leading, spacing: 4) {
                    let head = "\(short ? "Short" : "Long") \(SampleEngine.fn(g.d)) Δ at $\(String(format: "%.2f", px)), \(st.long)"
                    // "$917" is book money (the P&L a $1 rise costs): masked with privacy on, spoken "hidden".
                    let what = short ? "Each $1 up costs about \(BriefWords.plain("$" + SampleEngine.fn(g.d), privacy: privacy)) here. Each fix below shows what it costs and where it leaves you."
                        : late ? "Nothing to add here. The makes-the-most line comes back when IBKR data is live again."
                        : fl.map { "Nothing to add here. Drag right: it makes the most at $" + String(format: "%.2f", $0) + ", and each $1 above costs you." } ?? "Nothing to add here. It keeps making more across the chart."
                    Text(head)
                        .sType(SType(size: 20, weight: 700, line: 24, tracking: 0)).foregroundStyle(short ? S.red : S.ink)
                        .accessibilityLabel(PosSay.words(head))
                    Text(what)
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(BriefMask.spoken(what))
                }
                if !fixes.isEmpty {
                    FixesTiles(m: m, px: px, tt: tt, off: off, fixes: fixes, picked: $fix, privacy: privacy)
                }
                WallsByExpiry(m: m, kind: $wallsKind)
                WholeBook(m: m, privacy: privacy)
            }
            .padding(.horizontal, S.margin)
            .padding(.top, 16)
        }
    }

    /// The Walls layer's two chains: the nearest weekly and the nearest monthly.
    private var chainChips: [(Int, String)] {
        [m.chains.firstIndex { $0.kind == "Weekly" }, m.chains.firstIndex { $0.kind == "Monthly" }].compactMap { $0 }
            .map { ($0, "\(m.chains[$0].kind) · \(m.chains[$0].label)") }
    }

    /// A Greek and its value as one element, the sign said in words ("Delta, short 917"), not by colour only.
    private func greek(_ l: String, _ v: String, _ c: Color, said: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l).sType(BK.caption, tabular: false).foregroundStyle(S.secondary)
            Text(v).sType(SType(size: 15, weight: 700, line: 18, tracking: 0)).foregroundStyle(c)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l)
        .accessibilityValue(said)
    }
    private func legend(_ mark: String, _ t: String, _ c: Color) -> some View {
        HStack(spacing: 4) {
            Text(mark).sFont(12, .bold).foregroundStyle(c).accessibilityHidden(true)
            Text(t).sType(BK.label, tabular: false).foregroundStyle(S.secondary)
        }
    }
}

/// The payoff on the date picked (ink), today dashed, the turns-short line (orange dotted), the strikes under
/// it (sold solid, bought faint, red when hurting), a fix's preview dashed green, and the crosshair at the price.
/// Drag anywhere to set the price (steps of $0.05 under $50, $0.10 under $200, else $0.50).
private struct PositionsChart: View {
    let m: PositionsModel
    let tt: Double
    @Binding var price: Double?
    let off: Set<String>
    let flip: Double?
    let extra: [PositionsModel.Leg]
    var layer: String? = nil
    var chain = 0
    /// The date as words ("at the Oct 30 close", "today"), for the spoken summary.
    var phrase = ""
    var privacy = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    typealias Line = (k: Double, label: String, color: Color, dashed: Bool)

    /// The layer's price lines: this chain's walls, or the 20-day average and the month's high and low.
    private var layerLines: [Line] {
        if layer == "Walls" {
            guard m.chains.indices.contains(chain) else { return [] }
            let w = m.chains[chain], ex = w.label
            var out: [(Double, String, Color, Bool)] = []
            if let f = w.flip { out.append((f, "Flip · \(ex)", S.act, true)) }
            if let c = w.c { out.append((c, "Ceiling · \(ex)", S.navy, false)) }
            if let f = w.f { out.append((f, "Floor · \(ex)", S.brown, false)) }
            if let a = w.a { out.append((a, "Accelerator · \(ex)", S.brown.opacity(0.5), false)) }
            return out.filter { $0.0 >= m.X0 && $0.0 <= m.X1 }
        }
        if layer == "Technicals" {
            let tc = m.technicals
            return [(tc.sma, "20-day"), (tc.hi, "Month high"), (tc.lo, "Month low")].compactMap { v, l in
                v.map { ($0, l, S.teal, l != "20-day") } }.filter { $0.0 >= m.X0 && $0.0 <= m.X1 }
        }
        return []
    }

    /// Greedy lanes: each label takes the first row where it clears the one before it.
    static func lanes(_ items: [(x: CGFloat, w: CGFloat)]) -> [Int] {
        var ends: [CGFloat] = [], out: [Int] = []
        for it in items {
            let left = it.x - it.w / 2
            if let i = ends.firstIndex(where: { $0 + 4 < left }) { ends[i] = it.x + it.w / 2; out.append(i) }
            else { ends.append(it.x + it.w / 2); out.append(ends.count - 1) }
        }
        return out
    }

    /// VoiceOver's value: "35 dollars 28, up 3,686, long 5,934 delta"; the P&L "hidden" with privacy on.
    private var said: String {
        let p = price ?? m.S0, pl = m.pl(p, tt, off: off)
        return "\(PosSay.price(p)), \(privacy ? "hidden" : "\(pl < 0 ? "down" : "up") \(SampleEngine.fn(pl))"), \(PosSay.side(m.delta(p, tt, off: off))) delta"
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H: CGFloat = 190
            let sc = m.scale(off: off)
            let X = { (px: Double) -> CGFloat in CGFloat((px - m.X0) / (m.X1 - m.X0)) * W }
            let px = price ?? m.S0
            let xs = m.grid, lines = layerLines
            ZStack(alignment: .topLeading) {
                // The line, its dot and a fix's preview as one vector: a new date morphs them (S.lineMorph, 0.3 s,
                // instant under Reduce Motion). A leg or a fix switched on or off redraws at once, as before.
                PayoffCanvas(ys: PosVector(xs.map { m.pl($0, tt, off: off) } + [m.pl(px, tt, off: off)]
                                           + (extra.isEmpty ? [] : xs.map { m.pl($0, tt, off: off, extra: extra) })),
                             m: m, xs: xs, tt: tt, off: off, flip: flip, px: px, W: W, H: H, mn: sc.mn, mx: sc.mx, lines: lines)
                    .animation(nil, value: off)
                    .animation(nil, value: extra)
                    .animation(S.moving(S.lineMorph, reduce), value: tt)
                // Layer labels in lanes on chips, never overlapping. Keyed by label, so a new chain's labels fade
                // in where they belong instead of sliding over from the old ones.
                let sorted = lines.sorted { $0.k < $1.k }
                let lanes = Self.lanes(sorted.map { (X($0.k), CGFloat($0.label.count) * 5.6 + 14) })
                ForEach(Array(sorted.enumerated()), id: \.element.label) { i, l in
                    let lane = lanes[i]
                    Text(l.label).font(.system(size: 10, weight: .bold)).foregroundStyle(l.color)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(Capsule().fill(S.chip.opacity(0.95)))
                        .fixedSize()
                        .position(x: min(max(X(l.k), 40), W - 40), y: 10 + CGFloat(lane) * 22)
                }
                // The price axis.
                let step = [0.5, 1, 2, 2.5, 5, 10, 20, 25, 50].first { (m.X1 - m.X0) / $0 <= 5 } ?? 50
                ForEach(Array(stride(from: (m.X0 / step).rounded(.up) * step, through: m.X1, by: step)), id: \.self) { k in
                    Text("$\(String(format: k.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", k))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(S.secondary)
                        .position(x: X(k), y: H + 26)
                }
            }
            .contentShape(Rectangle())
            // A continuous drag: no haptic (Pass 5 haptics rule).
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let x = m.X0 + Double(max(0, min(1, v.location.x / W))) * (m.X1 - m.X0)
                let stp = m.S0 < 50 ? 0.05 : m.S0 < 200 ? 0.1 : 0.5
                let q = (x / stp).rounded() * stp
                if q != price { price = q }
            })
        }
        // One adjustable element: swipe up or down moves the price one step (0.05 under $50, 0.25 under $200,
        // else 1), on that step's grid and inside the chart's prices.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Payoff for \(m.company) \(PosSay.words(phrase))")
        .accessibilityValue(said)
        .accessibilityAdjustableAction { d in
            let p = price ?? m.S0
            let stp = p < 50 ? 0.05 : p < 200 ? 0.25 : 1
            let q = ((p + (d == .increment ? stp : -stp)) / stp).rounded() * stp
            price = min(max(q, m.X0), m.X1)
        }
    }
}

/// The payoff plot. Animatable: the P&L at each grid price, then the dot's P&L, then a fix preview's P&L at each
/// grid price (when one is picked) interpolate together, so the line morphs to a new date. Everything else draws
/// from the model at once, exactly as before.
private struct PayoffCanvas: View, Animatable {
    var ys: PosVector
    let m: PositionsModel
    let xs: [Double]
    let tt: Double
    let off: Set<String>
    let flip: Double?
    let px: Double
    let W: CGFloat
    let H: CGFloat
    let mn: Double
    let mx: Double
    let lines: [PositionsChart.Line]

    var animatableData: PosVector {
        get { ys }
        set { ys = newValue }
    }

    var body: some View {
        Canvas { ctx, _ in
            let X = { (p: Double) -> CGFloat in CGFloat((p - m.X0) / (m.X1 - m.X0)) * W }
            let Y = { (p: Double) -> CGFloat in CGFloat((mx - p) / (mx - mn)) * H }
            let n = xs.count, v = ys.v
            func path(_ f: (Int) -> Double) -> Path {
                var p = Path()
                for i in 0..<n {
                    let pt = CGPoint(x: X(xs[i]), y: max(-30, min(H + 20, Y(f(i)))))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                return p
            }
            let y0 = Y(0)
            let line = path { i in i < v.count ? v[i] : m.pl(xs[i], tt, off: off) }
            var area = line; area.addLine(to: CGPoint(x: W, y: y0)); area.addLine(to: CGPoint(x: 0, y: y0)); area.closeSubpath()
            ctx.drawLayer { c in c.clip(to: Path(CGRect(x: 0, y: -40, width: W, height: y0 + 40))); c.fill(area, with: .color(S.green.opacity(0.12))) }
            ctx.drawLayer { c in c.clip(to: Path(CGRect(x: 0, y: y0, width: W, height: H - y0 + 40))); c.fill(area, with: .color(S.red.opacity(0.10))) }
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y0)); $0.addLine(to: CGPoint(x: W, y: y0)) }, with: .color(S.secondary.opacity(0.3)), lineWidth: 1)
            if let f = flip, f <= m.X1 {
                ctx.stroke(Path { $0.move(to: CGPoint(x: X(f), y: 0)); $0.addLine(to: CGPoint(x: X(f), y: H)) },
                           with: .color(S.act), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
            }
            if tt > 0 { ctx.stroke(path { m.pl(xs[$0], 0, off: off) }, with: .color(S.ink.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) }
            if v.count >= 2 * n + 1 { ctx.stroke(path { v[n + 1 + $0] }, with: .color(S.green), style: StrokeStyle(lineWidth: 2, dash: [5, 3])) }
            ctx.stroke(line, with: .color(S.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            // Strike ticks under the plot.
            var seen: [Double: Int] = [:]
            for l in m.legs where l.ty != .shares && l.K >= m.X0 && l.K <= m.X1 {
                let i = seen[l.K, default: -1] + 1; seen[l.K] = i
                let x = X(l.K) + [0, -6, 6, -12][min(i, 3)]
                let hurt = m.legPL(l, px, tt) < -0.5 && !off.contains(l.id)
                let c: Color = hurt ? S.red : l.ty == .call ? S.navy : S.brown
                let o: Double = off.contains(l.id) ? 0.12 : l.q < 0 ? 1 : 0.4
                ctx.fill(Path(roundedRect: CGRect(x: x - 1.5, y: H + 5, width: 3, height: min(10, 3 + abs(l.q) / 60 * 7)), cornerRadius: 1.5), with: .color(c.opacity(o)))
            }
            // The layer's lines, under the crosshair.
            for l in lines {
                ctx.stroke(Path { $0.move(to: CGPoint(x: X(l.k), y: 0)); $0.addLine(to: CGPoint(x: X(l.k), y: H)) },
                           with: .color(l.color.opacity(0.85)), style: StrokeStyle(lineWidth: 1.2, dash: l.dashed ? [3, 3] : []))
            }
            // Crosshair.
            let cx = X(px)
            ctx.stroke(Path { $0.move(to: CGPoint(x: cx, y: 0)); $0.addLine(to: CGPoint(x: cx, y: H)) }, with: .color(S.ink), lineWidth: 1.5)
            let cy = Y(n < v.count ? v[n] : m.pl(px, tt, off: off))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10)), with: .color(S.ink))
        }
    }
}

/// A list of numbers SwiftUI can animate, element by element (a shorter list counts as zeros past its end).
private struct PosVector: VectorArithmetic {
    var v: [Double]
    init(_ v: [Double]) { self.v = v }

    static var zero: PosVector { PosVector([]) }
    static func + (a: PosVector, b: PosVector) -> PosVector { combine(a, b, +) }
    static func - (a: PosVector, b: PosVector) -> PosVector { combine(a, b, -) }
    mutating func scale(by r: Double) { for i in v.indices { v[i] *= r } }
    var magnitudeSquared: Double { v.reduce(0) { $0 + $1 * $1 } }

    private static func combine(_ a: PosVector, _ b: PosVector, _ f: (Double, Double) -> Double) -> PosVector {
        let n = max(a.v.count, b.v.count)
        return PosVector((0..<n).map { f($0 < a.v.count ? a.v[$0] : 0, $0 < b.v.count ? b.v[$0] : 0) })
    }
}

/// One stop per trading day up to the last sold expiry; the expiry Fridays tall; the date and "N trading days on".
private struct DateSlider: View {
    let m: PositionsModel
    @Binding var stop: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// One per day the thumb steps (finger or VoiceOver), for the selection haptic; the app's own moves make none.
    @State private var steps = 0
    var body: some View {
        let st = m.stops[stop]
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(st.long).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                Text(stop == 0 ? (m.weekend ? "next week" : "now") : "\(stop) trading day\(stop == 1 ? "" : "s") on").sType(BK.label, tabular: false).foregroundStyle(S.secondary)
            }
            GeometryReader { g in
                let n = m.stops.count - 1, w = g.size.width - 28
                ZStack(alignment: .leading) {
                    Capsule().fill(S.chip).frame(height: 4).padding(.horizontal, 14)
                    ForEach(m.stops.indices, id: \.self) { i in
                        Rectangle().fill(S.secondary.opacity(m.stops[i].friday ? 0.9 : 0.5)).frame(width: m.stops[i].friday ? 2 : 1, height: m.stops[i].friday ? 14 : 7)
                            .offset(x: 14 + w * CGFloat(i) / CGFloat(n) - 0.5, y: 14)
                    }
                    Circle().fill(.white).frame(width: 28, height: 28).shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .offset(x: w * CGFloat(stop) / CGFloat(n))
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let i = Int(((v.location.x - 14) / w * CGFloat(n)).rounded())
                    let c = min(max(i, 0), n)
                    if c != stop { withAnimation(S.moving(S.spring, reduce)) { stop = c }; steps += 1 }
                })
            }
            .frame(height: 30)
            HStack {
                Text(m.stops.first?.short ?? "").sType(BK.caption, tabular: false).foregroundStyle(S.secondary)
                Spacer()
                if let f = m.stops.dropLast().first(where: \.friday) {
                    Text(f.short).sType(SType(size: 11, weight: 700, line: 13, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Spacer()
                }
                Text(m.stops.last?.short ?? "").sType(BK.caption, tabular: false).foregroundStyle(S.secondary)
            }
        }
        .sensoryFeedback(.selection, trigger: steps)
        .accessibilityElement()
        .accessibilityLabel("Date")
        .accessibilityValue(PosSay.words(st.long))
        .accessibilityAdjustableAction { d in
            let c = min(max(stop + (d == .increment ? 1 : -1), 0), m.stops.count - 1)
            if c != stop { withAnimation(S.moving(S.spring, reduce)) { stop = c }; steps += 1 }
        }
    }
}

// MARK: - Legs

private struct LegsList: View {
    let m: PositionsModel
    let px: Double
    let tt: Double
    @Binding var off: Set<String>
    @Binding var filter: String
    let privacy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(["All", "Sold", "Long"], id: \.self) { f in
                    // Sections come and go and the page reflows: moving, so instant under Reduce Motion.
                    Button { withAnimation(S.moving(S.fade, reduce)) { filter = f } } label: {
                        Text(f).sFont(14, .semibold).foregroundStyle(filter == f ? S.sheetFill : S.ink)
                            .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(filter == f ? S.ink : S.chip))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
                Spacer()
                if !off.isEmpty {
                    Button { withAnimation(S.fade) { off = [] } } label: {
                        Text("\(off.count) leg\(off.count > 1 ? "s" : "") off · Show all").sFont(13, .semibold).foregroundStyle(S.act)
                    }.buttonStyle(.plain)
                }
            }
            let sold = m.legs.filter { $0.group == "s" }, long = m.legs.filter { $0.group == "l" }
            if filter != "Long" {
                if sold.isEmpty { section("Sold", "Nothing sold this week", S.secondary, []) }
                else { section("Sold", total(sold), totalColor(sold), sold) }
            }
            if filter != "Sold" { section("Long", total(long), totalColor(long), long) }
            if !m.ended.isEmpty && filter != "Long" { endedSection }
        }
        .sensoryFeedback(.selection, trigger: filter)
        .sensoryFeedback(.selection, trigger: off)
    }

    @State private var endedOpen = false
    /// The week that ended (weekend, answer 3): folded under "Ended Oct 30 · settled", each leg with how it ended.
    private var endedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The legs push the page down as they unfold: moving, so instant under Reduce Motion.
            Button { withAnimation(S.moving(S.fade, reduce)) { endedOpen.toggle() } } label: {
                HStack {
                    Text(m.endedLabel).sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Spacer()
                    Image(systemName: "chevron.down").sFont(13, .semibold).foregroundStyle(S.secondary)
                        .rotationEffect(.degrees(endedOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PosSay.words(m.endedLabel))
            .accessibilityValue(endedOpen ? "open" : "closed")
            .accessibilityHint(endedOpen ? "Folds the legs that ended" : "Shows how each leg ended")
            if endedOpen {
                ForEach(m.ended) { l in
                    let itm = l.ty == .call ? px > l.K : px < l.K
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l.title).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            .accessibilityLabel(PosSay.words(l.title))
                        Text(m.endedNotes[l.id] ?? (itm ? "Ended Oct 30, $\(String(format: "%.2f", abs(px - l.K))) in the money at $\(String(format: "%.2f", px)). Rolled before the close, so no shares went."
                                 : "Ended Oct 30, worth nothing at $\(String(format: "%.2f", px)): kept in full."))
                            .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(S.chip.opacity(0.6)))
                }
            }
        }
    }

    private func sum(_ ls: [PositionsModel.Leg]) -> Double { ls.filter { !off.contains($0.id) }.reduce(0) { $0 + m.legPL($1, px, tt) } }
    private func total(_ ls: [PositionsModel.Leg]) -> String {
        let v = sum(ls); return "\(v < 0 ? "Down" : "Up") \(BriefWords.plain("$" + SampleEngine.fn(v), privacy: privacy)) from today"
    }
    private func totalColor(_ ls: [PositionsModel.Leg]) -> Color { let v = sum(ls); return abs(v) < 0.5 ? S.secondary : v < 0 ? S.red : S.green }

    private func section(_ h: String, _ v: String, _ c: Color, _ ls: [PositionsModel.Leg]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(h).sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer()
                Text(v).sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(c)
                    .accessibilityLabel(BriefMask.spoken(v))
            }
            ForEach(ls) { l in legCard(l) }
        }
    }

    private func legCard(_ l: PositionsModel.Leg) -> some View {
        let isOff = off.contains(l.id), p = isOff ? 0 : m.legPL(l, px, tt), d = m.legDelta(l, px, tt)
        let hurt = p < -0.5 && !isOff
        let line: String = l.ty == .shares ? "Δ \(SampleEngine.fn(d)) · cost $\(String(format: "%.2f", l.K)), no decay" : "Δ \(SampleEngine.fn(d)) at $\(String(format: "%.2f", px))"
        return Button { withAnimation(S.fade) { if isOff { off.remove(l.id) } else { off.insert(l.id) } } } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.title).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text(isOff ? "Off · tap to add back" : line).sType(SType(size: 12, weight: 500, line: 16, tracking: 0))
                        .foregroundStyle(isOff ? S.secondary : d < 0 ? S.red : S.ink)
                }
                Spacer()
                BriefWords.line(isOff ? "Off" : abs(p) < 0.5 ? "$0" : "$" + SampleEngine.fn(p), privacy: privacy && !isOff && abs(p) >= 0.5)
                    .sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                    .foregroundStyle(isOff || abs(p) < 0.5 ? S.secondary : p < 0 ? S.red : S.green)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hurt ? S.red.opacity(0.08) : S.chip.opacity(0.8)))
            .opacity(isOff ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        // A toggle: "Calls 36 times 72, October 30", on or off. Its P&L and delta are in VoiceOver's More Content.
        .accessibilityLabel(PosSay.words(l.title))
        .accessibilityValue(isOff ? "off" : "on")
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint(isOff ? "Tap to add it back" : "Tap to switch it off")
        .accessibilityCustomContent("Profit or loss", isOff ? "off" : abs(p) < 0.5 ? "0 dollars" : PosSay.signed(p, privacy))
        .accessibilityCustomContent("Delta", PosSay.side(d))
    }
}

// MARK: - Fixes

private struct FixesTiles: View {
    let m: PositionsModel
    let px: Double
    let tt: Double
    let off: Set<String>
    let fixes: [PositionsModel.Fix]
    @Binding var picked: String?
    let privacy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fixes").sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 8) {
                ForEach(fixes) { f in
                    let ad = m.delta(px, tt, off: off, extra: f.extra), ap = m.pl(px, tt, off: off, extra: f.extra), on = picked == f.id
                    Button { withAnimation(S.fade) { picked = on ? nil : f.id } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.title).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            BriefWords.line("$" + SampleEngine.fn(f.cost), privacy: privacy).sType(SType(size: 17, weight: 800, line: 22, tracking: 0)).foregroundStyle(S.ink)
                            Text(f.act).sType(SType(size: 11, weight: 500, line: 14, tracking: 0), tabular: false).foregroundStyle(S.secondary).fixedSize(horizontal: false, vertical: true)
                            Text("Then \(ad < 0 ? "short" : "long") \(SampleEngine.fn(ad)) Δ · \(ap < 0 ? "down" : "up") \(BriefWords.plain("$" + SampleEngine.fn(ap), privacy: privacy))")
                                .sType(SType(size: 11, weight: 700, line: 14, tracking: 0), tabular: false).foregroundStyle(ad < 0 ? S.red : S.green)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(S.chip))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? S.ink : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    // One element; the picked fix is selected. Money "hidden" with privacy on.
                    .accessibilityLabel("\(f.title), costs \(PosSay.money(f.cost, privacy)). \(PosSay.words(f.act)). Then \(PosSay.side(ad)) delta, \(PosSay.signed(ap, privacy))")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityHint(on ? "Takes its preview off the chart" : "Previews it on the chart, dashed green")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: picked)
    }
}

// MARK: - Walls by expiry

private struct WallsByExpiry: View {
    let m: PositionsModel
    @Binding var kind: String
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// One wall on a row, keyed by what it is, so a row keeps its markers when the filter changes.
    private struct Mark: Identifiable { let id: String; let k: Double; let c: Color }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Walls by expiry").sType(BK.title, tabular: false).foregroundStyle(S.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Ceiling and floor for every chain, on the chart’s prices. Shaded is the move priced to that date. Tap a row to draw it on the chart.")
                .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(["All", "Weeklies", "Monthlies"], id: \.self) { k in
                    // Rows come, go and close up: moving, so instant under Reduce Motion.
                    Button { withAnimation(S.moving(S.fade, reduce)) { kind = k } } label: {
                        Text(k).sFont(14, .semibold).foregroundStyle(kind == k ? S.sheetFill : S.ink)
                            .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(kind == k ? S.ink : S.chip))
                    }.buttonStyle(.plain)
                    .accessibilityAddTraits(kind == k ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: kind)
            let rows = m.chains.enumerated().filter { kind == "All" || (kind == "Weeklies" ? $0.element.kind == "Weekly" : $0.element.kind == "Monthly") }
            if m.chains.isEmpty {
                Text("No walls saved for \(m.t) yet").sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
            }
            GeometryReader { g in
                let lw: CGFloat = 76, w = g.size.width - lw
                let X = { (px: Double) -> CGFloat in lw + CGFloat((px - m.X0) / (m.X1 - m.X0)) * w }
                ZStack(alignment: .topLeading) {
                    // A row per chain, keyed by the chain (not its place in the list), so a filter change fades rows in
                    // and out and closes them up instead of morphing one chain's markers into another's. Each row is
                    // one VoiceOver element that says what it draws.
                    ForEach(Array(rows.enumerated()), id: \.element.offset) { r, item in
                        let ex = item.element, wl = ex, y = CGFloat(r) * 42
                        let band = m.S0 * m.v * (Double(ex.trading) / 252).squareRoot()
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ex.label).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                Text("\(ex.kind) · \(ex.days)d").sType(SType(size: 11, weight: 500, line: 13, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                            }
                            .offset(y: 6)
                            Capsule().fill(S.chip).frame(width: max(0, X(min(m.X1, m.S0 + band)) - X(max(m.X0, m.S0 - band))), height: 10)
                                .offset(x: X(max(m.X0, m.S0 - band)), y: 16)
                            if wl.c == nil && wl.f == nil && wl.a == nil && wl.flip == nil {
                                // README 9.4: an expiry with no walls says so on its row.
                                Text("No walls saved for \(ex.label)").sType(SType(size: 12, weight: 500, line: 15, tracking: 0), tabular: false)
                                    .foregroundStyle(S.secondary).fixedSize().offset(x: lw + 8, y: 13)
                            }
                            if let fl = wl.flip, fl >= m.X0, fl <= m.X1 { Rectangle().fill(S.act).frame(width: 1, height: 18).opacity(0.8).offset(x: X(fl), y: 12) }
                            // Labels in lanes: a wall within 30 pt of the one before it puts its number below the bar.
                            let ms = [wl.a.map { Mark(id: "a", k: $0, c: S.brown.opacity(0.4)) }, wl.f.map { Mark(id: "f", k: $0, c: S.brown) },
                                      wl.c.map { Mark(id: "c", k: $0, c: S.navy) }].compactMap { $0 }.sorted { $0.k < $1.k }
                            ForEach(Array(ms.enumerated()), id: \.element.id) { i, mk in
                                let px = { (j: Int) in X(min(max(ms[j].k, m.X0), m.X1)) }
                                let close = i > 0 && abs(px(i) - px(i - 1)) < 30
                                // A wall with the next one close on its right puts its number on its left.
                                let left = !close && i + 1 < ms.count && abs(px(i + 1) - px(i)) < 30
                                marker(mk.k, mk.c, X, 0, below: close, left: left)
                            }
                            if r < rows.count - 1 { Rectangle().fill(S.hairline).frame(height: 0.5).offset(y: 41) }
                        }
                        .frame(width: g.size.width, height: 42, alignment: .topLeading)
                        .offset(y: y)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(rowWords(ex, band: band))
                    }
                    Rectangle().fill(S.ink).frame(width: 1, height: CGFloat(rows.count) * 42).offset(x: X(m.S0))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: CGFloat(rows.count) * 42)
            // A chart drawn to its 42 pt rows: its labels and key keep their size at any text size (Pass 5).
            .environment(\.sTypeScales, false)
            if !m.chains.isEmpty {
                HStack(spacing: 10) {
                    key(S.navy, "Ceiling"); key(S.brown, "Floor"); key(S.brown.opacity(0.4), "Accelerator"); key(S.act, "Flip"); key(S.ink, "Today")
                }
                .environment(\.sTypeScales, false)
            }
        }
        .briefCard()
    }

    @ViewBuilder private func marker(_ k: Double, _ c: Color, _ X: (Double) -> CGFloat, _ y: CGFloat, below: Bool = false, left: Bool = false) -> some View {
        let inRange = k >= m.X0 && k <= m.X1
        let x = X(min(max(k, m.X0), m.X1))
        let label = inRange ? String(format: "%g", k) : "\(String(format: "%g", k)) \(k > m.X1 ? "→" : "←")"
        RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 5, height: 16).offset(x: x - 2.5, y: y + 13)
        if left {
            Text(label).font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(c).fixedSize()
                .frame(width: 44, alignment: .trailing).offset(x: x - 49, y: y + 14)
        } else {
            Text(label).font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(c).fixedSize()
                .offset(x: below ? x - 6 : x + 5, y: below ? y + 29 : y + 14)
        }
    }
    /// A row as VoiceOver says it: "October 30, weekly, 3 days, ceiling 38 dollars, floor 33 dollars, priced move
    /// 33 dollars 20 to 37 dollars 36". A wall off the chart says so instead of an arrow.
    private func rowWords(_ ex: PositionsModel.Chain, band: Double) -> String {
        var s = "\(PosSay.words(ex.label)), \(ex.kind.lowercased()), \(ex.days) day\(ex.days == 1 ? "" : "s")"
        let walls = [("ceiling", ex.c), ("floor", ex.f), ("accelerator", ex.a), ("flip", ex.flip)].compactMap { n, k in k.map { (n, $0) } }
        if walls.isEmpty { return s + ", no walls saved" }
        for (n, k) in walls {
            s += ", \(n) \(PosSay.price(k))" + (k > m.X1 ? ", above the chart" : k < m.X0 ? ", below the chart" : "")
        }
        return s + ", priced move \(PosSay.price(m.S0 - band)) to \(PosSay.price(m.S0 + band))"
    }
    private func key(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 1.5).fill(c).frame(width: 4, height: 12); Text(t).sType(BK.caption, tabular: false).foregroundStyle(S.secondary) }
    }
}

// MARK: - The whole book in this name

private struct WholeBook: View {
    let m: PositionsModel
    let privacy: Bool
    var body: some View {
        let h = m.holdings()
        VStack(alignment: .leading, spacing: 8) {
            Text("Whole \(m.t) book").sType(BK.title, tabular: false).foregroundStyle(S.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Everything you hold in \(m.company), today").sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
            Text("Long").sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink).padding(.top, 6)
            ForEach([("Shares", h.sh), ("LEAPS", h.lp), ("OTM calls", h.oc), ("Insurance puts", h.ip)].filter { $0.1.value != 0 }, id: \.0) { r in
                BHairline()
                row(r.0, SampleEngine.fK(r.1.value), "\(r.1.today < 0 ? "▼" : "▲") \(SampleEngine.fK(r.1.today)) today", r.1.today < 0 ? S.red : S.green)
            }
            let sold = [("Calls", h.sc), ("Puts", h.sp)].filter { $0.1.value != 0 || $0.1.today != 0 }
            if !sold.isEmpty {
                Text("Sold · left to earn").sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink).padding(.top, 10)
                ForEach(sold, id: \.0) { r in
                    BHairline()
                    row(r.0, SampleEngine.fK(r.1.value), "\(SampleEngine.fK(r.1.today)) kept", S.green, after: " left to earn")
                }
            }
        }
        .briefCard()
    }
    /// One element: "Shares, 210 thousand dollars, up 1.2 thousand dollars today" (arrows said as up and down,
    /// money "hidden" with privacy on). `after` follows the value in speech only.
    private func row(_ l: String, _ v: String, _ sub: String, _ c: Color, after: String = "") -> some View {
        HStack {
            Text(l).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
            Spacer()
            BriefWords.line(v, privacy: privacy).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
            BriefWords.line(sub, privacy: privacy).sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(c).frame(minWidth: 100, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l)
        .accessibilityValue(BriefWords.speech(BriefWords.plain(v, privacy: privacy) + after + ", " + BriefWords.plain(sub, privacy: privacy)))
    }
}
