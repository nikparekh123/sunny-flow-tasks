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
import UIKit.UIGestureRecognizerSubclass

/// The colours SunnyPositions.dc.html pay45 draws with, light / dark, where they are not the app's shared tokens
/// (type pass, 8 Nov 2026). Text in the name's section is the design's MU (#6E6E73 / #AEAEB2); the book totals
/// above it are the cards' mu (#646469 / #98989D).
private enum PosC {
    static let mu = S.secondaryOnPage                                // MU
    static let rule = S.dynA(0x1D1D1F, 0.09, 0xFFFFFF, 0.12)         // PAL.rule: every 1 pt rule and the card's edges
    static let totRule = S.dynA(0x1D1D1F, 0.12, 0xFFFFFF, 0.14)      // TBL, between the book totals
    static let row = S.dynA(0x1D1D1F, 0.04, 0xFFFFFF, 0.06)          // ROWBG, a leg
    static let hurt = S.dynA(0xBC2E30, 0.08, 0xFF6961, 0.14)         // a leg that loses from today
    static let band = S.dynA(0x1D1D1F, 0.07, 0xFFFFFF, 0.10)         // pay.band, the priced move on a ladder row
    static let label = S.dynA(0xFFFFFF, 0.88, 0x1C1C1E, 0.85)        // LB45, under a wall or technicals label
    static let up = Color(hex: 0x327133).opacity(0.14)               // the payoff's area above zero (both modes)
    static let down = Color(hex: 0xBC2E30).opacity(0.12)             // and below
    static let moveBand = Color(hex: 0x2F5AA8).opacity(0.07)         // the priced move on the chart, Walls on
    static let slider = Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255)   // the date slider's track and ticks
}

/// A 1 pt rule in the design's PAL.rule (border-top: 1px solid rule).
private struct PosRule: View {
    var body: some View { Rectangle().fill(PosC.rule).frame(height: 1) }
}

struct BriefPositionsScreen: View {
    /// To do (10 Nov 2026): "7 to do" right of the title; nil hides it (not Nik's login).
    @Environment(\.todoTap) private var todoTap
    @State private var todo = TodoStore.shared
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
    @State private var layer: String? = nil
    @State private var fix: String?
    @State private var totalsMode = 0
    @State private var wallsKind = "All"
    /// The payoff chart's price range, an index into PositionsModel.zooms (Nov 8): ±12% each time the tab opens,
    /// kept across names while it stays open, as the design's z45.
    @State private var zoom = Self.debugZoom ?? PositionsModel.fitZoom
    /// Screens checked in the simulator: `-pzoom 4` opens the chart at ±25%.
    private static var debugZoom: Int? {
        #if DEBUG && targetEnvironment(simulator)
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-pzoom"), i + 1 < a.count, let z = Int(a[i + 1]) { return z }
        #endif
        return nil
    }

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
                    // SunnyPositions.dc.html nav.isBar: 28/32 heavy (README 7 says 34; the design's CSS wins), its box
                    // at y 148, 32 under the strip (44 + 72). The strip keeps a 72 pt slot under the safe area and draws
                    // `lift` higher, so the page pulls up by `lift` (as Home does).
                    // To do (10 Nov 2026): right of the large title, baseline to baseline, on the 20 pt margin.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Positions").sType(SType(size: 28, weight: 800, line: 32, tracking: -0.02), tabular: false)
                            .foregroundStyle(S.ink)
                            .accessibilityAddTraits(.isHeader)
                        if let tap = todoTap {
                            Spacer(minLength: 8)
                            TodoLink(open: todo.openCount, action: tap)
                        }
                    }
                    .padding(.horizontal, S.margin).padding(.top, brief.showsStrip ? 32 - AccountStrip.lift : 16)
                    if live && names.isEmpty {
                        // An empty book (Nicolay's, until he trades): one line, as agreed.
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nothing held yet").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            Text("Each name you hold shows here once IBKR reports it.").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
                        }
                        .padding(.horizontal, S.margin).padding(.top, 16)
                    }
                    if !names.isEmpty {
                        // Header gap 14 + the row's own 2 on top; 6 under it, then 20 to the logo strip.
                        BookTotalsRow(hs: totals, mode: $totalsMode, privacy: privacy).padding(.top, 14)
                        LogoStrip(items: strip, selected: name) { t in
                            if t != name { logoPicks += 1 }
                            withAnimation(S.fade) { name = t; price = nil; off = []; fix = nil }
                        }
                        .padding(.top, 20)
                        .sensoryFeedback(.selection, trigger: logoPicks)
                    }
                    if let m = model {
                        NameRow(m: m).padding(.horizontal, S.margin).padding(.top, 16)
                        if live, let t = brief.asOf() {
                            Text("As of \(Self.asOfWords(t)) · IBKR data is late").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.act)
                                .padding(.horizontal, S.margin).padding(.top, 4)
                        }
                        // In a ZStack so a new name crossfades in place (S.fade) instead of stacking under the old one.
                        ZStack(alignment: .topLeading) {
                            PositionsDetail(m: m, stop: Binding(get: { min(stop, m.stops.count - 1) }, set: { stop = $0 }), price: $price, off: $off,
                                            legFilter: $legFilter, layer: $layer, chain: $chain, fix: $fix, wallsKind: $wallsKind, zoom: $zoom,
                                            privacy: privacy, late: live && brief.asOf() != nil)
                                .id("\(acct)-\(name)")
                        }
                        .padding(.top, 16)
                    } else if live && !names.isEmpty, let b = brief.book {
                        Group {
                            if let e = brief.positions.error(b, name) { Text(e) } else { ProgressView().controlSize(.regular) }
                        }
                        .sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                // The account switch (README 11.4, block 33): this one page under the strip, never a second copy,
                // jumps to 15% and 28 pt toward the new account, then settles (S.switchFade 0.4 s, S.switchMove 0.5 s).
                // Every figure swaps at once, under the dip. Reduce Motion: the fade only.
                .opacity(faded ? 0.15 : 1)
                .offset(x: slid ? 28 * dipDir : 0)
            }
            .padding(.bottom, 120)
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
        .onAppear {
            // The chart opens at ±12% every time (design change 8); a price dragged outside that goes back to today.
            if zoom != PositionsModel.fitZoom && Self.debugZoom == nil {
                if let p = price, let m = model, abs(p / m.S0 - 1) > PositionsModel.zooms[PositionsModel.fitZoom] { price = nil }
                zoom = PositionsModel.fitZoom
            }
            arrive()
        }
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
    /// Book money as SampleEngine.fK writes it ($624, $5.9K, $13.7K, $379K, $1.2M): "13.7 thousand dollars",
    /// "1.2 million dollars", or "hidden".
    static func moneyK(_ v: Double, _ privacy: Bool) -> String {
        if privacy { return "hidden" }
        let a = abs(v)
        func one(_ x: Double) -> String { var t = String(format: "%.1f", x); if t.hasSuffix(".0") { t.removeLast(2) }; return t }
        if a >= 999_500 { return one(a / 1e6) + " million dollars" }
        if a >= 99_950 { return "\(Int((a / 1000).rounded())) thousand dollars" }
        if a >= 999.5 { return one(a / 1000) + " thousand dollars" }
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
        // Sold cycles with Long (the design's totG: "Calls · time value", then % today, then $ today; Nik, 8 Nov 2026).
        // Time value is the sales' time value alone (the engine's tv.sc and tv.sp), so Calls and Puts add up to Home's
        // Time value; % and $ today stay on what they would cost to buy back.
        let scT = hs.reduce(0) { $0 + $1.sc.today }, spT = hs.reduce(0) { $0 + $1.sp.today }
        let tsc = hs.reduce(0) { $0 + $1.timeSc }, tsp = hs.reduce(0) { $0 + $1.timeSp }
        let sold: [(String, Double, Bool)] = [("Calls", sc, scT, tsc), ("Puts", sp, spT, tsp)].filter { $0.1 != 0 }.map { it in
            (it.0, mode == 0 ? it.3 : mode == 1 ? (it.1 != 0 ? it.2 / it.1 * 100 : 0) : it.2, false)
        }
        // ⚠ A tap on the strip cycles the view. Not a Button around the ScrollView: inside a sideways ScrollView the
        // button never fired on the phone (Nik, 8 Nov 2026: "it was supposed to be tappable"); the tap sits on the row.
        let cycle = { withAnimation(S.fade) { mode = (mode + 1) % 3 } }
        Group {
            ScrollView(.horizontal) {
                // The design's totGrid: groups and items 16 apart with a 1 pt rule on the left of each after the
                // first; padding 2 top, 6 bottom, 40 right, and the last 36 pt fade out.
                HStack(alignment: .top, spacing: 0) {
                    group("Long", shown.map { it in
                        let lbl = mode == 0 ? (it.name == "Shares" ? "Shares · gain" : it.name == "Insurance puts" ? "Insurance puts" : "\(it.name) · time value") : "\(it.name) · \(views[mode])"
                        // The design's colour (tv$): time value in ink, the shares' gain and every % or $ change green or red.
                        return (lbl, it.v, mode == 1, mode != 0 || it.name == "Shares")
                    })
                    if !sold.isEmpty {
                        group("Sold", sold.map { ("\($0.0) · \(views[mode])", $0.1, mode == 1, mode != 0) })
                            .padding(.leading, 16)
                            .overlay(alignment: .leading) { Rectangle().fill(Self.rule).frame(width: 1) }
                    }
                }
                .padding(.leading, S.margin).padding(.trailing, 40)
                .padding(.top, 2).padding(.bottom, 6)
                .contentShape(Rectangle())
                .onTapGesture(perform: cycle)
            }
            .scrollIndicators(.hidden)
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 36)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: mode)
        // VoiceOver: the view on screen, then every figure with its sign as a word (money "hidden" with privacy on).
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, cycle)
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
        let s = sold.map { it -> String in
            let amount = mode == 1 ? "\(it.1 < 0 ? "down" : "up") \(String(format: "%.1f", abs(it.1))) percent"
                : mode == 2 ? PosSay.signed(it.1, privacy, k: true) : PosSay.moneyK(it.1, privacy)
            return "\(it.0) \(mode == 0 ? "time value" : ""), \(amount)"
        }
        var parts: [String] = []
        if !l.isEmpty { parts.append("Long. " + l.joined(separator: "; ")) }
        if !s.isEmpty { parts.append("Sold. " + s.joined(separator: "; ")) }
        return parts.joined(separator: ". ")
    }

    /// The design's TBL: rgba(29,29,31,.12) light, white 14% dark.
    static let rule = PosC.totRule

    /// Items: the label, the value, whether it is a %, and whether its colour is its sign (else ink, red below zero).
    private func group(_ h: String, _ items: [(String, Double, Bool, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(h).sType(SType(size: 13, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                    // 22/28 bold, 2, then the label 13/16 in the cards' mu; 16 either side of each rule.
                    VStack(alignment: .leading, spacing: 2) {
                        BriefWords.line(it.2 ? String(format: "%.1f%%", abs(it.1)) : SampleEngine.fK(it.1), privacy: privacy)
                            .sType(SType(size: 22, weight: 700, line: 28, tracking: -0.01))
                            .foregroundStyle(it.1 < 0 ? S.red : it.3 ? S.green : S.ink)
                        Text(it.0).sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                    }
                    .fixedSize()
                    .padding(.leading, i > 0 ? 16 : 0).padding(.trailing, 16)
                    .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Self.rule).frame(width: 1) } }
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
            // The design's strip: 52 wide buttons 14 apart, padding 8 20 6; a white 44 circle, the logo at 72%, a
            // 0.5 edge; the selected one ringed 2 pt in ink right on the circle; ticker 12/15 under it, 6 apart.
            HStack(alignment: .top, spacing: 14) {
                ForEach(items, id: \.t) { it in
                    let t = it.t, on = t == selected, warn = it.warn
                    Button { pick(t) } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                ZStack {
                                    Circle().fill(.white)
                                    if let img = UIImage(named: "logo-\(t)") {
                                        Image(uiImage: img).resizable().scaledToFit().frame(width: 44 * 0.72, height: 44 * 0.72)
                                    } else {
                                        Text(String(t.prefix(4))).font(.inter(11, 700)).foregroundStyle(Color(white: 0.11))
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5).padding(-0.25))
                                .overlay { if on { Circle().stroke(S.ink, lineWidth: 2).padding(-1) } }
                                if warn {
                                    // 11 pt at right -1, top -1, with a 2 pt ring of the page under it.
                                    Circle().fill(S.act).frame(width: 11, height: 11)
                                        .background(Circle().fill(S.sheetFill).padding(-2))
                                        .offset(x: 1, y: -1)
                                }
                            }
                            .accessibilityHidden(true)
                            Text(t).sType(SType(size: 12, weight: on ? 700 : 600, line: 15, tracking: 0), tabular: false)
                                .foregroundStyle(on ? S.ink : PosC.mu)
                        }
                        .frame(width: 52, alignment: .top)
                        .frame(minHeight: 66, alignment: .top)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(it.company + (warn ? ", past its best if it rises its priced move by Friday" : ""))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, S.margin)
            .padding(.top, 8).padding(.bottom, 6)
        }
        .scrollIndicators(.hidden)
    }
}

private struct NameRow: View {
    let m: PositionsModel
    var body: some View {
        let mv = (m.S0 - m.P0) / m.P0 * 100
        // The design's name row: ticker 20/24 bold, price 20 medium, the move 15 semibold, a space apart; the
        // strategy 15/20 medium on the right, centred on the row.
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(m.t).sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Text(String(format: "%.2f", m.S0)).sType(SType(size: 20, weight: 500, line: 24, tracking: 0)).foregroundStyle(PosC.mu)
                Text("\(mv < 0 ? "▼" : "▲") \(String(format: "%.1f", abs(mv)))%").sType(SType(size: 15, weight: 600, line: 20, tracking: 0))
                    .foregroundStyle(mv < 0 ? S.red : S.green)
            }
            .fixedSize()
            Spacer(minLength: 0)
            // The server sends its key ("rebound"); the design writes the name ("Rebound").
            if !m.strategy.isEmpty { Text(m.strategy.prefix(1).uppercased() + m.strategy.dropFirst()).sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(PosC.mu) }
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
    /// The chart's price range (PositionsModel.zooms), the screen's, so it holds across names.
    @Binding var zoom: Int
    let privacy: Bool
    /// IBKR is late (README 9.4): the last values stay, the makes-the-most line goes.
    var late = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// One per zoom step a finger (or VoiceOver) makes, for the selection haptic; the tab's own reset makes none.
    @State private var zoomSteps = 0

    /// The design's zTo: a step of the range, held to the steps the prices cover; a price dragged outside the new
    /// range goes back to today.
    private func zoomTo(_ n: Int) {
        let k = max(0, min(m.widestZoom, n)), z = min(zoom, m.widestZoom)
        guard k != z else { return }
        if let p = price, abs(p / m.S0 - 1) > PositionsModel.zooms[k] { price = nil }
        zoom = k
        zoomSteps += 1
    }

    var body: some View {
        // Everything on and under the chart reads the zoomed model (m45(t, zi)): the scale, the grid, the strikes,
        // walls, the turns-short price and the ladder's prices follow the range.
        let zi = min(zoom, self.m.widestZoom), m = self.m.zoomed(PositionsModel.zooms[zi])
        let st = m.stops[stop], px = price ?? m.S0, tt = st.tt
        let pl = m.pl(px, tt, off: off), g = m.greeks(px, tt, off: off), fl = late ? nil : m.flip(tt, off: off)
        let short = g.d < 0
        let fixes = m.fixes(px, tt, off: off)
        let picked = fixes.first { $0.id == fix }
        VStack(alignment: .leading, spacing: 0) {
            // The chart card, edge to edge on its own fill: padding 16 20 12, 10 between parts, a 0.5 rule above
            // and below (SunnyPositions.dc.html pay45).
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Text("\(pl < 0 ? "Down" : "Up") \(BriefWords.plain(SampleEngine.fK(pl), privacy: privacy))")
                        .sType(SType(size: 28, weight: 800, line: 36, tracking: -0.03))
                        .foregroundStyle(pl < 0 ? S.red : S.green)
                        .lineLimit(1).fixedSize()
                        .accessibilityLabel(privacy ? "\(pl < 0 ? "Down" : "Up"), hidden" : "\(pl < 0 ? "Down" : "Up") \(PosSay.moneyK(pl, false))")
                    Spacer(minLength: 0)
                    // ⚠ ONE HEIGHT WHILE SCRUBBING (Nik, 8 Nov 2026): "LULU at $110.74 · Tue Nov 10" went from one line to
                    // two as the big number changed width, and the chart under it jumped. The price and the date now sit
                    // on two lines of their own, and the block keeps the room of its longest state ("Losing, and rises
                    // cost you" on two lines), bottom aligned, so nothing below it moves.
                    ZStack(alignment: .bottomTrailing) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("Losing, and rises\ncost you").sType(SType(size: 13, weight: 700, line: 17, tracking: 0), tabular: false)
                            Text("X").sType(SType(size: 12, weight: 600, line: 16, tracking: 0))
                            Text("X").sType(SType(size: 12, weight: 600, line: 16, tracking: 0))
                        }
                        .hidden().accessibilityHidden(true)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(pl < 0 ? (short ? "Losing, and rises cost you" : "Losing") : short ? "Making, past its best" : "Long and making")
                                .sType(SType(size: 13, weight: 700, line: 17, tracking: 0), tabular: false)
                                .foregroundStyle(pl < 0 ? S.red : short ? S.act : S.green)
                                .multilineTextAlignment(.trailing).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Group {
                                Text("\(m.t) at $\(String(format: "%.2f", px))")
                                Text(st.long)
                            }
                            .sType(SType(size: 12, weight: 600, line: 16, tracking: 0))
                            .foregroundStyle(PosC.mu).lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    greek("Delta", SampleEngine.fn(g.d), g.d < 0 ? S.red : S.ink, said: PosSay.side(g.d))
                    greek("Theta", BriefWords.plain(SampleEngine.fK(g.th), privacy: privacy), g.th < 0 ? S.red : S.green, said: PosSay.signed(g.th, privacy, k: true))
                    greek("Gamma", SampleEngine.fn(g.g), g.g < 0 ? S.red : S.ink, said: PosSay.side(g.g))
                    greek("Vega", BriefWords.plain(SampleEngine.fK(g.vg), privacy: privacy), g.vg < 0 ? S.red : S.ink, said: PosSay.signed(g.vg, privacy, k: true))
                }
                // The plot 190, strike ticks to 206, 4, then the price axis 16.
                PositionsChart(m: m, tt: tt, price: $price, off: off, flip: fl, extra: picked?.extra ?? [], layer: layer, chain: chain,
                               phrase: st.phrase, privacy: privacy, zoom: zi, zoomTo: zoomTo)
                    .frame(height: 226)
                    .sensoryFeedback(.selection, trigger: zoomSteps)
                DateSlider(m: m, stop: $stop)
            }
            .padding(.horizontal, S.margin)
            .padding(.top, 16).padding(.bottom, 12)
            .background(S.sheetFill)
            .overlay(alignment: .top) { Rectangle().fill(PosC.rule).frame(height: 0.5).offset(y: -0.5) }
            .overlay(alignment: .bottom) { Rectangle().fill(PosC.rule).frame(height: 0.5).offset(y: 0.5) }

            // Everything under the card: one column, 12 apart, padding 0 20; the legs, the summary, Walls by expiry
            // and the whole book each open on a 1 pt rule.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(["Walls", "Technicals"], id: \.self) { l in
                        // Lines and labels come and go and the chain chips push the page down: moving, so instant under Reduce Motion.
                        Button { withAnimation(S.moving(S.fade, reduce)) { layer = layer == l ? nil : l } } label: {
                            Text(l).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                                .foregroundStyle(layer == l ? S.sheetFill : S.ink)
                                .padding(.horizontal, 14).frame(height: 32)
                                .background {
                                    if layer == l { Capsule().fill(S.ink) }
                                    else if scheme == .dark { Capsule().fill(S.track) }
                                    else {
                                        // White 55%, a white inner edge and a soft drop (the design's CHIP).
                                        Capsule().fill(S.tile)
                                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5))
                                            .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
                                    }
                                }
                                .frame(height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(layer == l ? .isSelected : [])
                    }
                }
                .padding(.vertical, -6)
                .sensoryFeedback(.selection, trigger: layer)
                if layer == "Walls" && chainChips.isEmpty {
                    Text("No walls saved for \(m.t) yet").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
                } else if layer == "Walls" {
                    // The design's wex row: "Weekly" then a chip per weekly chain, "Monthly" then the monthlies.
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(chainChips, id: \.0) { c in
                                if c.2 {
                                    Text(m.chains[c.0].kind).sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false)
                                        .foregroundStyle(PosC.mu).padding(.leading, c.0 == chainChips.first?.0 ? 0 : 6)
                                        .accessibilityHidden(true)
                                }
                                Button { withAnimation(S.moving(S.spring, reduce)) { chain = c.0 } } label: {
                                    Text(c.1).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                                        .foregroundStyle(chain == c.0 ? S.sheetFill : S.ink)
                                        .padding(.horizontal, 12).frame(height: 30)
                                        .background(Capsule().fill(chain == c.0 ? S.ink : S.track))
                                        .frame(height: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                .accessibilityLabel(PosSay.words("\(m.chains[c.0].kind) · \(c.1)"))
                                .accessibilityAddTraits(chain == c.0 ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, S.margin)
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -S.margin)
                    .padding(.top, -10).padding(.bottom, -6)
                    .sensoryFeedback(.selection, trigger: chain)
                }
                // The key wraps as the design's flex-wrap does (12 across, 4 down); "Tap a leg" is its last item.
                SXFlowGaps(column: 12, row: 4) {
                        legend("P&L on that date") { RoundedRectangle(cornerRadius: 2).fill(S.ink).frame(width: 14, height: 3) }
                        legend("Today") {
                            Path { $0.move(to: CGPoint(x: 0, y: 1)); $0.addLine(to: CGPoint(x: 14, y: 1)) }
                                .stroke(PosC.mu, style: StrokeStyle(lineWidth: 2, dash: [4, 3])).frame(width: 14, height: 2)
                        }
                        legend("Makes the most") { RoundedRectangle(cornerRadius: 1).fill(S.act).frame(width: 2, height: 12) }
                        legend("Hurting") { RoundedRectangle(cornerRadius: 2).fill(S.red).frame(width: 4, height: 12) }
                        Text("Tap a leg to switch it off").sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
                }
                VStack(alignment: .leading, spacing: 0) {
                    PosRule()
                    LegsList(m: m, px: px, tt: tt, off: $off, filter: $legFilter, privacy: privacy).padding(.top, 14)
                }
                VStack(alignment: .leading, spacing: 0) {
                    PosRule()
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            let head = "\(short ? "Short" : "Long") \(SampleEngine.fn(g.d)) Δ at $\(String(format: "%.2f", px)), \(st.long)"
                            // "$917" is book money (the P&L a $1 rise costs): masked with privacy on, spoken "hidden".
                            let what = short ? "Each $1 up costs about \(BriefWords.plain(SampleEngine.fK(g.d), privacy: privacy)) here. Each fix below shows what it costs and where it leaves you."
                                : late ? "Nothing to add here. The makes-the-most line comes back when IBKR data is live again."
                                : fl.flatMap { $0 <= m.X1 ? $0 : nil }.map { "Nothing to add here. Drag right: it makes the most at $" + String(format: "%.2f", $0) + ", and each $1 above costs you." } ?? "Nothing to add here. It keeps making more across the chart."
                            Text(head)
                                .sType(SType(size: 20, weight: 700, line: 24, tracking: 0)).foregroundStyle(short ? S.red : S.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(PosSay.words(head))
                            Text(what)
                                .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(BriefMask.spoken(what))
                        }
                        if !fixes.isEmpty {
                            FixesTiles(m: m, px: px, tt: tt, off: off, fixes: fixes, picked: $fix, privacy: privacy)
                        }
                    }
                    .padding(.top, 16)
                }
                WallsByExpiry(m: m, kind: $wallsKind, chain: $chain, layer: $layer)
                WholeBook(m: m, privacy: privacy)
            }
            .padding(.horizontal, S.margin)
            .padding(.top, 16)
        }
    }

    @Environment(\.colorScheme) private var scheme

    /// The Walls layer's chains: every weekly, then every monthly; `true` on the first of each kind (its label).
    private var chainChips: [(Int, String, Bool)] {
        let w = m.chains.indices.filter { m.chains[$0].kind == "Weekly" }, mo = m.chains.indices.filter { m.chains[$0].kind == "Monthly" }
        return w.enumerated().map { ($1, m.chains[$1].label, $0 == 0) } + mo.enumerated().map { ($1, m.chains[$1].label, $0 == 0) }
    }

    /// A Greek and its value as one element, the sign said in words ("Delta, short 917"), not by colour only.
    /// The design's: label 11/14 semibold, value 15/19 heavy, four equal columns 8 apart.
    private func greek(_ l: String, _ v: String, _ c: Color, said: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l).sType(SType(size: 11, weight: 600, line: 14, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
            Text(v).sType(SType(size: 15, weight: 800, line: 19, tracking: 0)).foregroundStyle(c).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l)
        .accessibilityValue(said)
    }
    /// A key: its mark (drawn, as in the design) 5 before the words, 12/16 medium.
    private func legend<M: View>(_ t: String, @ViewBuilder mark: () -> M) -> some View {
        HStack(spacing: 5) {
            mark().accessibilityHidden(true)
            Text(t).sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
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
    /// The zoom step on screen (PositionsModel.zooms) and the step to go to (the design's zTo).
    var zoom = PositionsModel.fitZoom
    var zoomTo: (Int) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// A pinch under way: the fingers' distance across when it began and the step it began on (the design's _pz45).
    @State private var pinch: (d0: CGFloat, z0: Int)?
    /// Once a pinch begins, the finger left on the chart does not scrub until every finger has lifted (_on45).
    @State private var scrubOff = false

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
            if let a = w.a { out.append((a, "Accel. · \(ex)", S.brown, false)) }
            return out.filter { $0.0 >= m.X0 && $0.0 <= m.X1 }
        }
        if layer == "Technicals" {
            let tc = m.technicals
            return [(tc.sma, "20-day"), (tc.hi, "Month high"), (tc.lo, "Month low")].compactMap { v, l in
                v.map { ($0, l, S.teal, true) } }.filter { $0.0 >= m.X0 && $0.0 <= m.X1 }
        }
        return []
    }

    /// The design's lane45: each label takes the first lane where it clears every label already there by 4 pt.
    /// `x` is the label's left edge (clamped into the plot), `w` its width.
    static func lanes(_ items: [(x: CGFloat, w: CGFloat)]) -> [Int] {
        var placed: [(lane: Int, x0: CGFloat, x1: CGFloat)] = [], out: [Int] = []
        for it in items {
            var ln = 0
            while placed.contains(where: { $0.lane == ln && it.x < $0.x1 + 4 && it.x + it.w > $0.x0 - 4 }) { ln += 1 }
            placed.append((ln, it.x, it.x + it.w)); out.append(ln)
        }
        return out
    }

    /// VoiceOver's value: "35 dollars 28, up 3,686, long 5,934 delta"; the P&L "hidden" with privacy on.
    private var said: String {
        let p = price ?? m.S0, pl = m.pl(p, tt, off: off)
        return "\(PosSay.price(p)), \(PosSay.signed(pl, privacy, k: true)), \(PosSay.side(m.delta(p, tt, off: off))) delta"
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H: CGFloat = 190
            let sc = m.scale(off: off)
            let X = { (px: Double) -> CGFloat in CGFloat((px - m.X0) / (m.X1 - m.X0)) * W }
            let px = price ?? m.S0
            let xs = m.grid, lines = layerLines
            // The move priced to the date picked, shaded while Walls is on (one formula: iv × √(trading days ÷ 252)).
            let sdx = m.S0 * m.v * (max(tt, 1) / 252).squareRoot()
            let band: (CGFloat, CGFloat)? = layer == "Walls" ? (X(max(m.X0, m.S0 - sdx)), X(min(m.X1, m.S0 + sdx))) : nil
            ZStack(alignment: .topLeading) {
                // The line, its dot and a fix's preview as one vector: a new date morphs them (S.lineMorph, 0.3 s,
                // instant under Reduce Motion). A leg or a fix switched on or off redraws at once, as before.
                PayoffCanvas(ys: PosVector(xs.map { m.pl($0, tt, off: off) } + [m.pl(px, tt, off: off)]
                                           + (extra.isEmpty ? [] : xs.map { m.pl($0, tt, off: off, extra: extra) })),
                             m: m, xs: xs, tt: tt, off: off, flip: flip, px: px, W: W, H: H, mn: sc.mn, mx: sc.mx, lines: lines, band: band)
                    .animation(nil, value: off)
                    .animation(nil, value: extra)
                    .animation(S.moving(S.lineMorph, reduce), value: tt)
                // Layer labels in lanes, never overlapping (lane45): walls from the top, left-aligned 2 right of their
                // line, lanes going down 16; technicals centred on theirs from 16 above the axis, lanes going up.
                // Keyed by label, so a new chain's labels fade in where they belong.
                let walls = layer == "Walls"
                let sorted = lines.sorted { $0.k < $1.k }
                let widths = sorted.map { CGFloat($0.label.count) * 6.6 + 8 }
                let lefts = sorted.indices.map { i in min(max(0, walls ? X(sorted[i].k) + 2 : X(sorted[i].k) - widths[i] / 2), W - widths[i]) }
                let lanes = Self.lanes(sorted.indices.map { (lefts[$0], widths[$0]) })
                ForEach(Array(sorted.enumerated()), id: \.element.label) { i, l in
                    Text(l.label).font(.inter(11, 700, tabular: true)).foregroundStyle(l.color)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 3).frame(height: 14)
                        .background(RoundedRectangle(cornerRadius: 4).fill(PosC.label))
                        .offset(x: lefts[i], y: walls ? -2 + CGFloat(lanes[i]) * 16 : H - 16 - CGFloat(lanes[i]) * 16)
                }
                // The price axis: 12/16 semibold, 4 under the ticks; centred, or flush at either end.
                let step = [0.5, 1, 2, 2.5, 5, 10, 20, 25, 50].first { (m.X1 - m.X0) / $0 <= 5 } ?? 50
                ForEach(Array(stride(from: (m.X0 / step).rounded(.up) * step, through: m.X1, by: step)), id: \.self) { k in
                    let x = X(k)
                    Text("$\(String(format: k.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", k))")
                        .font(.inter(12, 600, tabular: true)).foregroundStyle(PosC.mu)
                        .fixedSize().frame(height: 16)
                        .alignmentGuide(.leading) { d in -(x < 14 ? x : x > W - 14 ? x - d.width : x - d.width / 2) }
                        .offset(y: 210)
                }
            }
            .contentShape(Rectangle())
            // One finger scrubs the price, a continuous drag: no haptic (Pass 5 haptics rule). A new touch scrubs
            // again once a pinch has ended.
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if v.translation == .zero && pinch == nil { scrubOff = false }
                    guard !scrubOff else { return }
                    let x = m.X0 + Double(max(0, min(1, v.location.x / W))) * (m.X1 - m.X0)
                    let stp = m.S0 < 50 ? 0.05 : m.S0 < 200 ? 0.1 : 0.5
                    let q = (x / stp).rounded() * stp
                    if q != price { price = q }
                }
                .onEnded { _ in if pinch == nil { scrubOff = false } })
            // Design change 8 (Nov 8): a pinch steps the range one step per 1.3× of the fingers' distance across,
            // narrower as they spread (pm: z0 - round(log(d / d0) / log(1.3))); a double tap goes back to ±12%.
            .gesture(PinchAcross { d in
                guard let d else { pinch = nil; return }
                guard let p = pinch else { pinch = (max(8, d), zoom); scrubOff = true; return }
                zoomTo(p.z0 - Int((log(max(8, d) / p.d0) / log(1.3) + 0.5).rounded(.down)))
            })
            .gesture(DoubleTap { zoomTo(PositionsModel.fitZoom) })
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
        // The pinch for VoiceOver (the design's - and + keys on the web).
        .accessibilityAction(named: "Wider price range") { zoomTo(zoom + 1) }
        .accessibilityAction(named: "Narrower price range") { zoomTo(zoom - 1) }
        // While zoomed: the glass capsule top right of the plot, "±25% · Fit"; a tap goes back to ±12%.
        .overlay(alignment: .topTrailing) {
            if zoom != PositionsModel.fitZoom { ZoomFit(r: PositionsModel.zooms[zoom]) { zoomTo(PositionsModel.fitZoom) } }
        }
    }
}

/// The zoom's way back (SunnyPositions.dc.html, pay.zf): 28 tall, 10 either side, radius 14, 13/16 semibold ink in
/// tabular figures, on the glass the cards on Positions use (PAL.card white 78% / #2C2C2E 78% over a blur, PAL.cardSh:
/// a 1 pt white inner edge, a hairline outside in light, a soft drop); pressed, it shrinks to 95%.
private struct ZoomFit: View {
    let r: Double
    let tap: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pct = Int((r * 100).rounded()), dark = scheme == .dark
        Button(action: tap) {
            Text("±\(pct)% · Fit").sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.ink)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 10).frame(minHeight: 28)
                .background {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(dark ? Color(hex: 0x2C2C2E).opacity(0.78) : Color.white.opacity(0.78))
                    }
                    .overlay(Capsule().strokeBorder(Color.white.opacity(dark ? 0.12 : 0.75), lineWidth: 1))
                    .overlay { if !dark { Capsule().stroke(Color(hex: 0x1D1D1F).opacity(0.06), lineWidth: 0.5).padding(-0.25) } }
                    .shadow(color: .black.opacity(dark ? 0 : 0.04), radius: 1.5, y: 1)
                    .shadow(color: .black.opacity(dark ? 0.5 : 0.12), radius: 9, y: 10)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(ZoomPress())
        .accessibilityLabel("Price range plus or minus \(pct) percent. Back to plus or minus 12 percent")
    }
}

/// style-active: transform scale(.95), at once (no transition in the design).
private struct ZoomPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

/// The design's onDoubleClick (pay.zd): two taps on the chart go back to ±12%. UIKit's double tap, alongside the
/// one-finger scrub (each tap still sets the price, as each click does in the design).
private struct DoubleTap: UIGestureRecognizerRepresentable {
    let action: () -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> PinchAcross.Coordinator { PinchAcross.Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let g = UITapGestureRecognizer()
        g.numberOfTapsRequired = 2
        g.delegate = context.coordinator
        return g
    }
    func handleUIGestureRecognizerAction(_ g: UITapGestureRecognizer, context: Context) {
        if g.state == .ended { action() }
    }
}

/// A two-finger pinch measured as the design measures it (pay.pd / pay.pm): the distance across between the two
/// fingers, nil when it ends. It runs alongside the one-finger scrub and the double tap, never the page's scroll.
/// Its first reading is the distance when the second finger landed (pointerdown), not when the pinch is recognised.
private struct PinchAcross: UIGestureRecognizerRepresentable {
    let changed: (CGFloat?) -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> Recognizer {
        let g = Recognizer()
        g.delegate = context.coordinator
        return g
    }
    func handleUIGestureRecognizerAction(_ g: Recognizer, context: Context) {
        switch g.state {
        case .began:
            if let d0 = g.landed { changed(d0) }
            if let d = g.across { changed(d) }
        case .changed:
            if let d = g.across { changed(d) }
        default: changed(nil)
        }
    }
    final class Recognizer: UIPinchGestureRecognizer {
        /// The distance across when the second finger touched down.
        private(set) var landed: CGFloat?
        private var down: [UITouch] = []
        var across: CGFloat? {
            guard numberOfTouches >= 2, let v = view else { return nil }
            return abs(location(ofTouch: 0, in: v).x - location(ofTouch: 1, in: v).x)
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            down += touches
            if down.count == 2, landed == nil, let v = view { landed = abs(down[0].location(in: v).x - down[1].location(in: v).x) }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { super.touchesEnded(touches, with: event); lift(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { super.touchesCancelled(touches, with: event); lift(touches) }
        override func reset() { super.reset(); down = []; landed = nil }
        private func lift(_ t: Set<UITouch>) { down.removeAll { t.contains($0) }; if down.isEmpty { landed = nil } }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { !(o.view is UIScrollView) }
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
    /// The priced move's band (x from, x to) while Walls is on.
    var band: (CGFloat, CGFloat)? = nil

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
            func vline(_ x: CGFloat) -> Path { Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: H)) } }
            // The priced move while Walls is on (navy 7%).
            if let b = band { ctx.fill(Path(CGRect(x: b.0, y: 0, width: max(0, b.1 - b.0), height: H)), with: .color(PosC.moveBand)) }
            var area = line; area.addLine(to: CGPoint(x: W, y: y0)); area.addLine(to: CGPoint(x: 0, y: y0)); area.closeSubpath()
            ctx.drawLayer { c in c.clip(to: Path(CGRect(x: -4, y: -40, width: W + 8, height: y0 + 40))); c.fill(area, with: .color(PosC.up)) }
            ctx.drawLayer { c in c.clip(to: Path(CGRect(x: -4, y: y0, width: W + 8, height: 260))); c.fill(area, with: .color(PosC.down)) }
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y0)); $0.addLine(to: CGPoint(x: W, y: y0)) }, with: .color(PosC.mu.opacity(0.45)), lineWidth: 1)
            // The layer's lines: walls solid at 70%, technicals dashed 3 3 at 80%.
            for l in lines {
                ctx.stroke(vline(X(l.k)), with: .color(l.color.opacity(l.dashed ? 0.8 : 0.7)), style: StrokeStyle(lineWidth: 1, dash: l.dashed ? [3, 3] : []))
            }
            if let f = flip, f <= m.X1 {
                ctx.stroke(vline(X(f)), with: .color(S.act), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
            }
            if tt > 0 { ctx.stroke(path { m.pl(xs[$0], 0, off: off) }, with: .color(PosC.mu.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])) }
            if v.count >= 2 * n + 1 { ctx.stroke(path { v[n + 1 + $0] }, with: .color(S.green), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 5])) }
            ctx.stroke(line, with: .color(S.ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            // Crosshair at the price: a 1 pt line; the dot r 5.5 stroked 2 in the card's fill (ink 9 across, ring to 13).
            let cx = X(px)
            ctx.stroke(vline(cx), with: .color(S.ink), lineWidth: 1)
            let cy = max(0, min(H, Y(n < v.count ? v[n] : m.pl(px, tt, off: off))))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 6.5, y: cy - 6.5, width: 13, height: 13)), with: .color(S.sheetFill))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 4.5, y: cy - 4.5, width: 9, height: 9)), with: .color(S.ink))
            // The axis rule, today's price on it, then the strike ticks (4 wide, round ends, from 195).
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: H)); $0.addLine(to: CGPoint(x: W, y: H)) }, with: .color(PosC.rule), lineWidth: 1)
            let nx = X(m.S0)
            ctx.fill(Path(ellipseIn: CGRect(x: nx - 3.5, y: H - 3.5, width: 7, height: 7)), with: .color(S.ink))
            var seen: [Double: Int] = [:]
            for l in m.legs where l.ty != .shares && l.K >= m.X0 && l.K <= m.X1 {
                let i = seen[l.K, default: -1] + 1; seen[l.K] = i
                let x = X(l.K) + [0, -6, 6, -12][min(i, 3)]
                let hurt = m.legPL(l, px, tt) < -0.5 && !off.contains(l.id)
                let c: Color = hurt ? S.red : l.ty == .call ? S.navy : S.brown
                let o: Double = off.contains(l.id) ? 0.12 : l.q < 0 ? 1 : 0.4
                let len = min(10, 3 + abs(l.q) / 60 * 7)
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: H + 5)); $0.addLine(to: CGPoint(x: x, y: H + 5 + len)) },
                           with: .color(c.opacity(o)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
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
/// The design's: the date 14/18 bold and the count 12/16, 2, a 40 pt slider (track 4 at 12, inset 14, ink up to a
/// white 38 x 24 thumb at 14, ticks from 27: 10 on the Fridays, the first in ink, 5 elsewhere), then its labels
/// 12/16, 2 up into it: the first flush left, the first Friday centred on its stop in ink, the last flush right.
private struct DateSlider: View {
    let m: PositionsModel
    @Binding var stop: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// One per day the thumb steps (finger or VoiceOver), for the selection haptic; the app's own moves make none.
    @State private var steps = 0
    var body: some View {
        let st = m.stops[stop], n = max(1, m.stops.count - 1)
        let firstFri = m.stops.dropLast().firstIndex(where: \.friday)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(st.long).sType(SType(size: 14, weight: 700, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer(minLength: 12)
                Text(stop == 0 ? (m.weekend ? "next week" : "now") : "\(stop) trading day\(stop == 1 ? "" : "s") on")
                    .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
            }
            GeometryReader { g in
                let w = g.size.width - 28, f = CGFloat(stop) / CGFloat(n)
                ZStack(alignment: .topLeading) {
                    Capsule().fill(PosC.slider.opacity(0.2)).frame(width: w, height: 4).offset(x: 14, y: 12)
                    Capsule().fill(S.ink).frame(width: max(0, w * f), height: 4).offset(x: 14, y: 12)
                    ForEach(m.stops.indices, id: \.self) { i in
                        let tall = m.stops[i].friday, first = i == firstFri
                        RoundedRectangle(cornerRadius: 1)
                            .fill(first ? S.ink : PosC.slider.opacity(tall ? 0.7 : 0.5))
                            .frame(width: 2, height: tall ? 10 : 5)
                            .offset(x: 14 + w * CGFloat(i) / CGFloat(n) - 1, y: 27)
                    }
                    Capsule().fill(.white).frame(width: 38, height: 24)
                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.16), radius: 4, y: 3)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                        .offset(x: 14 + w * f - 19, y: 2)
                }
                .frame(width: g.size.width, height: 40, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let i = Int(((v.location.x - 14) / w * CGFloat(n)).rounded())
                    let c = min(max(i, 0), n)
                    if c != stop { withAnimation(S.moving(S.spring, reduce)) { stop = c }; steps += 1 }
                })
            }
            .frame(height: 40)
            GeometryReader { g in
                let w = g.size.width - 28
                let lab = { (t: String, bold: Bool) in
                    Text(t).sType(SType(size: 12, weight: bold ? 700 : 500, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(bold ? S.ink : PosC.mu).fixedSize()
                }
                ZStack(alignment: .topLeading) {
                    lab(m.stops.first?.short ?? "", false).offset(x: 14)
                    if let i = firstFri {
                        let x = 14 + w * CGFloat(i) / CGFloat(n)
                        lab(m.stops[i].short, true).alignmentGuide(.leading) { d in -(x - d.width / 2) }
                    }
                    lab(m.stops.last?.short ?? "", false).alignmentGuide(.leading) { d in -(14 + w - d.width) }
                }
                .frame(width: g.size.width, alignment: .topLeading)
            }
            .frame(height: 16)
            .padding(.top, -2)
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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.sTypeScales) private var scales
    /// "Δ 1,925" in a leg's line: 13 semibold, tabular, at the phone's text size where the screen follows it.
    private var deltaFont: Font {
        let t = SType(size: 13, weight: 600, line: 18, tracking: 0)
        return (scales ? t.scaled(dts) : t).font(tabular: true)
    }

    var body: some View {
        // The design's legs: All · Sold · Long (32 tall, 6 apart), then "N legs off · Show all" on its own line,
        // then a section per group, 12 apart.
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(["All", "Sold", "Long"], id: \.self) { f in
                    // Sections come and go and the page reflows: moving, so instant under Reduce Motion.
                    Button { withAnimation(S.moving(S.fade, reduce)) { filter = f } } label: {
                        Text(f).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                            .foregroundStyle(filter == f ? S.sheetFill : S.ink)
                            .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(filter == f ? S.ink : S.track))
                            .frame(height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
            }
            .padding(.vertical, -6)
            if !off.isEmpty {
                Button { withAnimation(S.fade) { off = [] } } label: {
                    Text("\(off.count) leg\(off.count > 1 ? "s" : "") off · Show all")
                        .sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        .underline().frame(minHeight: 32)
                }.buttonStyle(.plain)
            }
            let sold = m.legs.filter { $0.group == "s" }, long = m.legs.filter { $0.group == "l" }
            if filter != "Long" {
                if sold.isEmpty { section("Sold", "Nothing sold this week", PosC.mu, []) }
                else { section("Sold", total(sold), totalColor(sold), sold) }
            }
            if filter != "Sold" { section("Long", total(long), totalColor(long), long) }
            if !m.ended.isEmpty && filter != "Long" { endedSection }
        }
        .sensoryFeedback(.selection, trigger: filter)
        .sensoryFeedback(.selection, trigger: off)
    }

    /// The design's leg row fill (ROWBG): ink 4%, white 6% in dark.
    private var rowFill: Color { PosC.row }

    @State private var endedOpen = false
    /// The week that ended (weekend, answer 3): folded under "Ended Oct 30 · settled", each leg with how it ended.
    private var endedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The legs push the page down as they unfold: moving, so instant under Reduce Motion.
            Button { withAnimation(S.moving(S.fade, reduce)) { endedOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(m.endedLabel).sType(SType(size: 13, weight: 700, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    // The design's 10 x 10 chevron.
                    Path { p in p.move(to: CGPoint(x: 2.5, y: 3.5)); p.addLine(to: CGPoint(x: 5, y: 6.5)); p.addLine(to: CGPoint(x: 7.5, y: 3.5)) }
                        .stroke(S.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 10, height: 10)
                        .rotationEffect(.degrees(endedOpen ? 180 : 0))
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PosSay.words(m.endedLabel))
            .accessibilityValue(endedOpen ? "open" : "closed")
            .accessibilityHint(endedOpen ? "Folds the legs that ended" : "Shows how each leg ended")
            if endedOpen {
                ForEach(m.ended) { l in
                    let itm = l.ty == .call ? px > l.K : px < l.K
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.title).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            .accessibilityLabel(PosSay.words(l.title))
                        // The leg's own expiry (the model's ended day), never a fixed date.
                        let ended = l.ex.isEmpty ? "Ended" : "Ended \(l.ex)"
                        Text(m.endedNotes[l.id] ?? (itm ? "\(ended), $\(String(format: "%.2f", abs(px - l.K))) in the money at $\(String(format: "%.2f", px)). Rolled before the close, so no shares went."
                                 : "\(ended), worth nothing at $\(String(format: "%.2f", px)): kept in full."))
                            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(rowFill))
                }
            }
        }
    }

    private func sum(_ ls: [PositionsModel.Leg]) -> Double { ls.filter { !off.contains($0.id) }.reduce(0) { $0 + m.legPL($1, px, tt) } }
    private func total(_ ls: [PositionsModel.Leg]) -> String {
        let v = sum(ls); return "\(v < 0 ? "Down" : "Up") \(BriefWords.plain(SampleEngine.fK(v), privacy: privacy)) from today"
    }
    private func totalColor(_ ls: [PositionsModel.Leg]) -> Color { let v = sum(ls); return abs(v) < 0.5 ? PosC.mu : v < 0 ? S.red : S.green }

    /// A group: its head (13/18 bold, the total 13/18 semibold on the right, 28 tall), then its rows, 6 apart.
    private func section(_ h: String, _ v: String, _ c: Color, _ ls: [PositionsModel.Leg]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(h).sType(SType(size: 13, weight: 700, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer(minLength: 0)
                Text(v).sType(SType(size: 13, weight: 600, line: 18, tracking: 0)).foregroundStyle(c).lineLimit(1)
                    .accessibilityLabel(BriefMask.spoken(v))
            }
            .frame(minHeight: 28)
            ForEach(ls) { l in legCard(l) }
        }
    }

    /// A leg: padding 12 14, radius 14; the title 15/20 semibold and the P&L 15/20 bold on one baseline, 2, then
    /// "Δ 1,925" 13/18 semibold (red when it hurts) and the rest 13/18 medium secondary; switched off it fades to 45%
    /// and says so 2 under, in the same grid (12/16 bold).
    private func legCard(_ l: PositionsModel.Leg) -> some View {
        let isOff = off.contains(l.id), p = isOff ? 0 : m.legPL(l, px, tt), d = m.legDelta(l, px, tt)
        let hurt = p < -0.5 && !isOff
        let rest: String = l.ty == .shares ? " · cost $\(String(format: "%.2f", l.K)), no decay" : " at $\(String(format: "%.2f", px))"
        return Button { withAnimation(S.fade) { if isOff { off.remove(l.id) } else { off.insert(l.id) } } } label: {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(l.title).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        BriefWords.line(isOff ? "Off" : abs(p) < 0.5 ? "$0" : SampleEngine.fK(p), privacy: privacy && !isOff && abs(p) >= 0.5)
                            .sType(SType(size: 15, weight: 700, line: 20, tracking: 0))
                            .foregroundStyle(isOff || abs(p) < 0.5 ? PosC.mu : p < 0 ? S.red : S.green)
                    }
                    // The Δ part at 600 by its own font: `.fontWeight` cannot reach Inter's weight axis.
                    (Text("Δ \(SampleEngine.fn(d))").font(deltaFont).foregroundStyle(d < 0 ? S.red : S.ink)
                     + Text(rest).foregroundStyle(PosC.mu))
                        .sType(SType(size: 13, weight: 500, line: 18, tracking: 0))
                        .fixedSize(horizontal: false, vertical: true)
                    if isOff {
                        Text("Off · tap to add back").sType(SType(size: 12, weight: 700, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    }
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hurt ? PosC.hurt : rowFill))
            .opacity(isOff ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        // A toggle: "Calls 36 times 72, October 30", on or off. Its P&L and delta are in VoiceOver's More Content.
        .accessibilityLabel(PosSay.words(l.title))
        .accessibilityValue(isOff ? "off" : "on")
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint(isOff ? "Tap to add it back" : "Tap to switch it off")
        .accessibilityCustomContent("Profit or loss", isOff ? "off" : abs(p) < 0.5 ? "0 dollars" : PosSay.signed(p, privacy, k: true))
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
        // The design's fixes: one row each, 10 apart, padding 12 14, radius 14: the name and its cost 15/20 bold on
        // one line, what it is 13/18, where it leaves you 13/18 bold; the picked one white with a 2 pt ink ring.
        VStack(alignment: .leading, spacing: 10) {
            Text("Fixes").sType(SType(size: 13, weight: 700, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(fixes) { f in
                let ad = m.delta(px, tt, off: off, extra: f.extra), ap = m.pl(px, tt, off: off, extra: f.extra), on = picked == f.id
                Button { withAnimation(S.fade) { picked = on ? nil : f.id } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(f.title).sType(SType(size: 15, weight: 700, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            Spacer(minLength: 0)
                            BriefWords.line(SampleEngine.fK(f.cost), privacy: privacy).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                        }
                        Text(f.act).sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Then \(ad < 0 ? "short" : "long") \(SampleEngine.fn(ad)) Δ · \(ap < 0 ? "down" : "up") \(BriefWords.plain(SampleEngine.fK(ap), privacy: privacy))")
                            .sType(SType(size: 13, weight: 700, line: 18, tracking: 0)).foregroundStyle(ad < 0 ? S.red : S.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? S.sheetFill : S.track))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? S.ink : .clear, lineWidth: 2))
                    .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 6, y: 4)
                }
                .buttonStyle(.plain)
                // One element; the picked fix is selected. Money "hidden" with privacy on.
                .accessibilityLabel("\(f.title), costs \(PosSay.moneyK(f.cost, privacy)). \(PosSay.words(f.act)). Then \(PosSay.side(ad)) delta, \(PosSay.signed(ap, privacy, k: true))")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityHint(on ? "Takes its preview off the chart" : "Previews it on the chart, dashed green")
            }
        }
        .sensoryFeedback(.selection, trigger: picked)
    }
}

// MARK: - Walls by expiry

private struct WallsByExpiry: View {
    let m: PositionsModel
    @Binding var kind: String
    /// The chain the chart draws, and the chart's layer: a row tapped draws that chain (Walls on).
    @Binding var chain: Int
    @Binding var layer: String?
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.colorScheme) private var scheme
    /// One wall on a row, keyed by what it is, so a row keeps its markers when the filter changes.
    private struct Mark: Identifiable { let id: String; let k: Double; let c: Color; let o: Double }
    /// The design's ladder: a 80 pt label column, rows 44 tall, the axis 22 under them.
    private static let lw: CGFloat = 80, rowH: CGFloat = 44, axisH: CGFloat = 22
    var body: some View {
        // Opens on a 1 pt rule, 16 above the title; 10 between parts (SunnyPositions.dc.html, Walls by expiry).
        VStack(alignment: .leading, spacing: 0) {
            PosRule()
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Walls by expiry").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        .accessibilityAddTraits(.isHeader)
                    // With no walls saved, only the title and "No walls saved for NKE yet" (README 9.4: nothing stands in).
                    if !m.chains.isEmpty {
                        Text("Ceiling and floor for every chain, on the chart’s prices. Shaded is the move priced to that date. Tap a row to draw it on the chart.")
                            .sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(PosC.mu).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !m.chains.isEmpty {
                HStack(spacing: 6) {
                    ForEach(["All", "Weeklies", "Monthlies"], id: \.self) { k in
                        // Rows come, go and close up: moving, so instant under Reduce Motion.
                        Button { withAnimation(S.moving(S.fade, reduce)) { kind = k } } label: {
                            Text(k).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                                .foregroundStyle(kind == k ? S.sheetFill : S.ink)
                                .padding(.horizontal, 12).frame(height: 30).background(Capsule().fill(kind == k ? S.ink : S.track))
                                .frame(height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityAddTraits(kind == k ? .isSelected : [])
                    }
                }
                .padding(.vertical, -6)
                .sensoryFeedback(.selection, trigger: kind)
                }
                let rows = m.chains.enumerated().filter { kind == "All" || (kind == "Weeklies" ? $0.element.kind == "Weekly" : $0.element.kind == "Monthly") }
                if m.chains.isEmpty {
                    Text("No walls saved for \(m.t) yet").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
                } else {
                    ladder(rows)
                        // A chart drawn to its 44 pt rows: its labels and key keep their size at any text size (Pass 5).
                        .environment(\.sTypeScales, false)
                    SXFlowGaps(column: 12, row: 4) {
                        key("Ceiling") { RoundedRectangle(cornerRadius: 3).fill(S.navy).frame(width: 6, height: 12) }
                        key("Floor") { RoundedRectangle(cornerRadius: 3).fill(S.brown).frame(width: 6, height: 12) }
                        key("Accelerator") { RoundedRectangle(cornerRadius: 3).fill(S.brown).opacity(0.45).frame(width: 6, height: 12) }
                        key("Flip") { dashedTick(S.act).frame(width: 2, height: 12) }
                        key("Today") { Rectangle().fill(S.ink).opacity(0.5).frame(width: 1.5, height: 12) }
                    }
                    .environment(\.sTypeScales, false)
                }
            }
            .padding(.top, 16)
        }
    }

    private func ladder(_ rows: [EnumeratedSequence<[PositionsModel.Chain]>.Element]) -> some View {
        GeometryReader { g in
            let lw = Self.lw, w = g.size.width - lw
            let X = { (px: Double) -> CGFloat in CGFloat((px - m.X0) / (m.X1 - m.X0)) * w }
            ZStack(alignment: .topLeading) {
                // A row per chain, keyed by the chain (not its place in the list), so a filter change fades rows in
                // and out and closes them up instead of morphing one chain's markers into another's. Each row is one
                // VoiceOver element that says what it draws; a tap draws its walls on the chart.
                ForEach(Array(rows.enumerated()), id: \.element.offset) { r, item in
                    let ex = item.element, idx = item.offset, on = layer == "Walls" && chain == idx
                    let band = m.S0 * m.v * (Double(ex.trading) / 252).squareRoot()
                    let lo = X(max(m.X0, m.S0 - band)), hi = X(min(m.X1, m.S0 + band))
                    Button {
                        withAnimation(S.moving(S.fade, reduce)) { chain = idx; layer = "Walls" }
                    } label: {
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(on ? S.ink.opacity(scheme == .dark ? 0.08 : 0.05) : .clear)
                            if r > 0 { Rectangle().fill(PosC.rule).frame(height: 1) }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(ex.label).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                Text("\(ex.kind) · \(ex.days)d").sType(SType(size: 11, weight: 500, line: 14, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
                            }
                            .fixedSize()
                            .offset(x: 2, y: 7)
                            ZStack(alignment: .topLeading) {
                                Capsule().fill(PosC.band).frame(width: max(0, hi - lo), height: 12).offset(x: lo, y: 16)
                                if ex.c == nil && ex.f == nil && ex.a == nil && ex.flip == nil {
                                    // README 9.4: an expiry with no walls says so on its row.
                                    Text("No walls saved for \(ex.label)").sType(SType(size: 12, weight: 500, line: 15, tracking: 0), tabular: false)
                                        .foregroundStyle(PosC.mu).fixedSize().offset(x: 8, y: 14)
                                }
                                if let fl = ex.flip, fl >= m.X0, fl <= m.X1 { dashedTick(S.act).frame(width: 2, height: 22).offset(x: X(fl) - 0.75, y: 11) }
                                ForEach(marks(ex)) { mk in marker(mk, X, w) }
                            }
                            .offset(x: lw)
                        }
                        .frame(width: g.size.width, height: Self.rowH, alignment: .topLeading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(y: CGFloat(r) * Self.rowH)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rowWords(ex, band: band))
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint("Draws its walls on the chart")
                }
                Rectangle().fill(S.ink).opacity(0.5).frame(width: 1.5, height: CGFloat(rows.count) * Self.rowH)
                    .offset(x: lw + X(m.S0) - 0.75)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                // The axis: a rule, the chart's prices 11/14 semibold 4 under it.
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(PosC.rule).frame(width: w, height: 1)
                    let step = [0.5, 1, 2, 2.5, 5, 10, 20, 25, 50].first { (m.X1 - m.X0) / $0 <= 5 } ?? 50
                    ForEach(Array(stride(from: (m.X0 / step).rounded(.up) * step, through: m.X1, by: step)), id: \.self) { k in
                        let x = X(k)
                        Text("$\(String(format: k.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", k))")
                            .font(.inter(11, 600, tabular: true)).foregroundStyle(PosC.mu)
                            .fixedSize().frame(height: 14)
                            .alignmentGuide(.leading) { d in -(x < 14 ? x : x > w - 14 ? x - d.width : x - d.width / 2) }
                            .offset(y: 4)
                    }
                }
                .frame(width: w, height: Self.axisH, alignment: .topLeading)
                .offset(x: lw, y: CGFloat(rows.count) * Self.rowH)
                .accessibilityHidden(true)
            }
        }
        .frame(height: CGFloat(rows.count) * Self.rowH + Self.axisH)
    }

    /// A row's walls: accelerator (45%), floor, ceiling. In range the ceiling's number sits right of its marker, the
    /// floor's left, the accelerator has none; a wall off the chart pins 3 in from the edge at 50% with "40 →".
    private func marks(_ ex: PositionsModel.Chain) -> [Mark] {
        [ex.a.map { Mark(id: "a", k: $0, c: S.brown, o: 0.45) }, ex.f.map { Mark(id: "f", k: $0, c: S.brown, o: 1) },
         ex.c.map { Mark(id: "c", k: $0, c: S.navy, o: 1) }].compactMap { $0 }
    }

    @ViewBuilder private func marker(_ mk: Mark, _ X: (Double) -> CGFloat, _ w: CGFloat) -> some View {
        let hiO = mk.k > m.X1, loO = mk.k < m.X0
        let x = hiO ? w - 3 : loO ? 3 : X(mk.k)
        let label = hiO ? "\(String(format: "%g", mk.k)) →" : loO ? "← \(String(format: "%g", mk.k))" : mk.id == "a" ? "" : String(format: "%g", mk.k)
        RoundedRectangle(cornerRadius: 3).fill(mk.c).frame(width: 6, height: 14).opacity(hiO || loO ? 0.5 : mk.o).offset(x: x - 3, y: 15)
        if !label.isEmpty {
            // 11/18 bold: right of the ceiling (+3), left of the floor (-3), inward from a pinned one (6).
            let right = !hiO && (loO || mk.id == "c")
            // Offsets only, so a label past either end never moves the row's layout.
            Text(label).font(.inter(11, 700, tabular: true)).foregroundStyle(mk.c).fixedSize()
                .frame(width: 64, height: 18, alignment: right ? .leading : .trailing)
                .offset(x: right ? x + (loO ? 6 : 3) : x - 64 - (hiO ? 6 : 3), y: 13)
        }
    }
    /// The flip: a 1.5 pt dashed line, as the design's border-left dashed.
    private func dashedTick(_ c: Color) -> some View {
        GeometryReader { g in
            Path { $0.move(to: CGPoint(x: 0.75, y: 0)); $0.addLine(to: CGPoint(x: 0.75, y: g.size.height)) }
                .stroke(c, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
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
    private func key<M: View>(_ t: String, @ViewBuilder mark: () -> M) -> some View {
        HStack(spacing: 5) {
            mark().accessibilityHidden(true)
            Text(t).sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
        }
    }
}

// MARK: - The whole book in this name

private struct WholeBook: View {
    let m: PositionsModel
    let privacy: Bool
    var body: some View {
        let h = m.holdings()
        // The design's whole book: a 1 pt rule, 16, the title 20/24 and its line 13/18 6 apart, then each group 8
        // down: its head 13/18 bold, 4, rows of 9 + 20 + 9 on a rule.
        VStack(alignment: .leading, spacing: 0) {
            PosRule()
            VStack(alignment: .leading, spacing: 6) {
                Text("Whole \(m.t) book").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Everything you hold in \(m.company), today").sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(PosC.mu)
                let long = [("Shares", h.sh), ("LEAPS", h.lp), ("OTM calls", h.oc), ("Insurance puts", h.ip)].filter { $0.1.value != 0 || $0.1.today != 0 }
                if !long.isEmpty {
                    group("Long") {
                        ForEach(long, id: \.0) { r in
                            row(r.0, SampleEngine.fK(r.1.value), "\(r.1.today < 0 ? "▼" : "▲") \(SampleEngine.fK(r.1.today)) today", r.1.today < 0 ? S.red : S.green)
                        }
                    }
                }
                // Left to earn is the sales' time value alone (an in the money sale's intrinsic part is not earnable).
                let sold = [("Calls", h.sc, h.timeSc), ("Puts", h.sp, h.timeSp)].filter { $0.1.value != 0 || $0.1.today != 0 }
                if !sold.isEmpty {
                    group("Sold · left to earn") {
                        ForEach(sold, id: \.0) { r in
                            row(r.0, SampleEngine.fK(r.2), "\(SampleEngine.fK(r.1.today)) kept", S.green, after: " left to earn")
                        }
                    }
                }
            }
            .padding(.top, 16)
        }
    }
    private func group<C: View>(_ h: String, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(h).sType(SType(size: 13, weight: 700, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink).padding(.bottom, 4)
            rows()
        }
        .padding(.top, 8)
    }
    /// One element: "Shares, 210 thousand dollars, up 1.2 thousand dollars today" (arrows said as up and down,
    /// money "hidden" with privacy on). `after` follows the value in speech only.
    private func row(_ l: String, _ v: String, _ sub: String, _ c: Color, after: String = "") -> some View {
        VStack(spacing: 0) {
            PosRule()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(l).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Spacer(minLength: 0)
                BriefWords.line(v, privacy: privacy).sType(SType(size: 15, weight: 700, line: 20, tracking: 0)).foregroundStyle(S.ink)
                BriefWords.line(sub, privacy: privacy).sType(SType(size: 13, weight: 600, line: 18, tracking: 0)).foregroundStyle(c)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)   // wraps at large text (Audit 6)
                    .frame(minWidth: 96, alignment: .trailing)
            }
            .padding(.vertical, 9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l)
        .accessibilityValue(BriefWords.speech(BriefWords.plain(v, privacy: privacy) + after + ", " + BriefWords.plain(sub, privacy: privacy)))
    }
}
