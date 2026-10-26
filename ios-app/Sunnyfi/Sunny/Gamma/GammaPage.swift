//
//  GammaPage.swift
//  Sunny
//
//  Block 13h (handoff 32) · one held name on the Gamma tab, in the design's order: the price line, the
//  expiry chips, the summary (regime, drift, the flip, tape coverage), the read, the price ladder, this week's
//  plan, the hedges, your position, the walls table, who is trading, data quality, how labels held. Every
//  number is the server's: the walls from the tape (gamma_view_day), the plan from sunny-home's one hedge
//  function, so Gamma, To do and Δ Γ agree. Text outside the cards starts on the cards' inner line.
//

import SwiftUI
import Charts
import Supabase

struct GammaPage: View {
    let t: String
    let home: HomePayload
    let name: PName?
    @Environment(HomeRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var g: GammaName?
    @State private var loaded = false
    @State private var sessions: Int?
    @State private var view = "weeklies"
    /// Off by default (Nik, 26 Oct 2026); the toggle turns it on.
    @State private var compare = false
    @State private var trades = false

    /// A name read in the last 5 minutes opens with its data at once (no blank page while swiping).
    init(t: String, home: HomePayload, name: PName?) {
        self.t = t; self.home = home; self.name = name
        let c = GammaData.cached(t)
        _g = State(initialValue: c)
        _loaded = State(initialValue: c != nil)
    }

    private var plan: NamePlan? { home.plan?.value?[t] }
    private var inner: CGFloat { S.margin + 20 }

    var body: some View {
        // Lazy: a page lays out only the sections on screen (it is about 6,000 pt tall; drawing all of it as it slid in
        // made the swipe jerk, Nik 26 Oct 2026).
        LazyVStack(alignment: .leading, spacing: 16) {
            if let g, let v = g.views[view] ?? g.views["weeklies"] ?? g.views.values.first {
                header(v)
                chips(g)
                summary(g, v)
                GammaRead(t: t, v: v, hist: g.history[viewKey(g)] ?? []).padding(.horizontal, S.margin)
                ladderCard(g, v)
                if let p = plan { GammaPlanCard(t: t, p: p, v: g.views[p.week] ?? g.views["weeklies"], earnings: nextEarnings).padding(.horizontal, S.margin) }
                if let p = plan { GammaHedges(t: t, p: p, spot: v.spot, dg: name?.dg, earnings: nextEarnings).padding(.horizontal, S.margin) }
                GammaPosition(t: t, legs: home.legs.filter { $0.ticker == t }, dg: name?.dg, name: home.writes.names.first { $0.ticker == t }?.insights?.value?.name, today: home.today).padding(.horizontal, S.margin)
                GammaWallsTable(v: v, hist: g.history[viewKey(g)] ?? [], view: viewKey(g)).padding(.horizontal, S.margin)
                GammaWho(t: t, flow: g.views["weeklies"]?.flow, profile: home.flowProfile?.value?[t]).padding(.horizontal, S.margin)
                GammaQuality(v: g.views["weeklies"] ?? v).padding(.horizontal, S.margin)
                GammaHeld(sessions: sessions, track: g.views["weeklies"]?.track).padding(.horizontal, S.margin)
                Text("Open interest updates overnight. Tape-based labels update during the day.")
                    .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                    .foregroundStyle(S.muted).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.horizontal, inner)
            } else if loaded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t).sType(SType(size: 28, weight: 800, line: 32, tracking: -0.01), tabular: false).foregroundStyle(S.ink)
                    Text("No tape read for \(t) yet. The walls are built after each close and every 30 minutes in the session.")
                        .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, inner)
            }
        }
        .task(id: t) { await load() }
        .onChange(of: router.gammaView) { _, v in if let v { view = v; router.gammaView = nil } }
        .onAppear { if let v = router.gammaView { view = v; router.gammaView = nil } }
    }

    private func load() async {
        if g == nil, let c = GammaData.cached(t) { g = c; loaded = true }
        g = try? await GammaData.load(t, today: home.today)
        loaded = true
        if let r = try? await SupabaseService.client.from("gamma_view_day").select("day", head: true, count: .exact)
            .eq("ticker", value: t).eq("view", value: "weeklies").execute() { sessions = r.count }
    }

    private var nextEarnings: String? { home.writes.names.first { $0.ticker == t }?.nextEarnings?.date }
    /// The view the ladder and table read: an expiry, 'weeklies' or 'all'.
    private func viewKey(_ g: GammaName) -> String { g.views[view] != nil ? view : "weeklies" }

    // MARK: Header: the ticker and the price as of the read

    private func header(_ v: GammaView) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).sType(SType(size: 28, weight: 800, line: 32, tracking: -0.01), tabular: false).foregroundStyle(S.ink)
            Text("$\(PF.price(v.spot)) · " + GammaText.asOf(g?.day ?? home.today, today: home.today))
                .sType(SType(size: 15, weight: 500, line: 20, tracking: 0)).foregroundStyle(S.muted)
        }
        .padding(.horizontal, inner)
    }

    // MARK: Expiry chips: the weeklies (selected together as the Weeklies view) and the monthlies

    private func chips(_ g: GammaName) -> some View {
        let dates = g.views.keys.filter { $0.first?.isNumber == true }.sorted()
        let weeklies = g.views["weeklies"]?.expiries ?? Array(dates.filter { !WallsData.isMonthly($0) }.prefix(3))
        let monthly = dates.filter { WallsData.isMonthly($0) }
        let spans = { (e: String) -> Bool in nextEarnings.map { $0 <= e } ?? false }
        let on = { (e: String) -> Bool in self.view == "weeklies" ? weeklies.contains(e) : self.view == e }
        return VStack(alignment: .leading, spacing: 8) {
            group("Weeklies", weeklies, on: on, spans: spans)
            if !monthly.isEmpty { group("Monthlies", monthly, on: on, spans: spans) }
            if (weeklies + monthly).contains(where: spans) {
                HStack(spacing: 6) {
                    Circle().fill(S.ink).frame(width: 5, height: 5)
                    Text("Earnings report falls before this expiry").sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted)
                }
                .padding(.leading, inner)
            }
        }
    }

    private func group(_ h: String, _ es: [String], on: @escaping (String) -> Bool, spans: @escaping (String) -> Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(h).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                .padding(.leading, inner)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(es, id: \.self) { e in
                        let sel = on(e)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(reduce ? nil : S.standard(0.25)) { view = (view == e ? "weeklies" : e) }
                        } label: {
                            HStack(spacing: 6) {
                                Text(PF.monthDay(e)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                                if spans(e) { Circle().fill(sel ? S.paper : S.ink).frame(width: 5, height: 5) }
                            }
                            .foregroundStyle(sel ? S.paper : S.ink)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(Capsule().fill(sel ? S.ink : S.tileWalls))
                            .overlay(Capsule().strokeBorder(sel ? .clear : S.line, lineWidth: 0.5))
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(POpacityPress())
                        .accessibilityAddTraits(sel ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .padding(.horizontal, inner)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Summary: the view, its chips, the flip and coverage

    private func summary(_ g: GammaName, _ v: GammaView) -> some View {
        let key = viewKey(g)
        let title = key == "weeklies" ? "Weeklies" : key == "all" ? "All" : PF.monthDay(key)
        let sub = key == "weeklies" ? v.expiries.map(PF.monthDay).joined(separator: ", ")
            : key == "all" ? "every expiry to 45 days" : PWords.n(WallsData.days(home.today, key), "day")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).sType(SType(size: 28, weight: 800, line: 32, tracking: -0.01), tabular: false).foregroundStyle(S.ink)
                Text(sub).sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.muted)
            }
            PWrap(spacing: 8) {
                if let r = v.regime { GammaChip(text: GammaText.regime(r), dot: r == "calmer" ? S.blue : S.orange) }
                if let d = v.drift { GammaChip(text: GammaText.drift(d.pct), dot: d.pct > 1 ? S.blue : d.pct < -1 ? S.orange : S.muted) }
                if let fp = home.flowProfile?.value?[t] { GammaChip(text: fp.label, dot: S.muted) }
            }
            if disagree(g) {
                HStack(spacing: 6) {
                    Circle().fill(S.orange).frame(width: 7, height: 7)
                    Text("Weekly and monthly disagree").sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(S.orangeDeep)
                }
            }
            if let f = v.flip {
                Text("Flip \(PF.price(f)), " + GammaText.vs(f, v.spot) + " price")
                    .sType(SType(size: 15, weight: 500, line: 20, tracking: 0)).foregroundStyle(S.ink)
            }
            if let c = v.coverage {
                Text(c < 0.5 ? "Low tape coverage today (\(Int((c * 100).rounded()))%). Each wall is read from its own strike; a strike too thin to read shows Unclear."
                              : "Tape coverage \(Int((c * 100).rounded()))% of today's option volume")
                    .sType(SType(size: 13, weight: c < 0.5 ? 600 : 500, line: 18, tracking: 0))
                    .foregroundStyle(c < 0.5 ? S.orangeDeep : S.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if key == "all", let r = v.rolloff {
                Text("Rolls off \(PF.monthDay(r.exp)): \(Int((r.share * 100).rounded()))% of the gamma expires then")
                    .sType(SType(size: 13, weight: 600, line: 18, tracking: 0)).foregroundStyle(S.ink)
            }
        }
        .padding(.horizontal, inner)
    }

    /// The weeklies and the monthly read the 1st walls differently.
    private func disagree(_ g: GammaName) -> Bool {
        guard let w = g.views["weeklies"], let m = g.views.keys.filter({ $0.first?.isNumber == true && WallsData.isMonthly($0) }).sorted().first,
              let mv = g.views[m] else { return false }
        let f = { (v: GammaView, side: String) in v.walls.first { $0.side == side && $0.rank == 1 }?.label }
        return f(w, "call") != f(mv, "call") || f(w, "put") != f(mv, "put")
    }

    // MARK: The price ladder card

    private func ladderCard(_ g: GammaName, _ v0: GammaView) -> some View {
        let dates = g.views.keys.filter { $0.first?.isNumber == true }.sorted()
        let monthly = dates.first { WallsData.isMonthly($0) }
        let hedge = plan?.hedge?.exp ?? plan?.insurance?.exp
        let segs = ["weeklies"] + [monthly, hedge].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } + ["all"]
        let key = viewKey(g), v = g.views[key] ?? v0
        let legs = home.legs.filter { $0.ticker == t && $0.expiry > home.today }
        return SCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Price ladder").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                GammaSegments(items: segs.map { ($0, $0 == "weeklies" ? "Weeklies" : $0 == "all" ? "All" : PF.monthDay($0)) }, on: segs.contains(key) ? key : "weeklies") { s in
                    withAnimation(reduce ? nil : S.standard(0.25)) { view = s }
                }
                Toggle(isOn: $compare) {
                    Text("Compare with 1 week ago").sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                }.tint(S.green)
                Toggle(isOn: $trades) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show your trades").sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        Text(GammaText.tradesLine(legs)).sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                    }
                }.tint(S.green)
                if let p = v.priced {
                    Text("Priced move by \(PWays.weekday(p.exp)) ±\(F.trim(p.sd1Pct))%, lighter to ±\(F.trim(p.sd1Pct * 1.5))% (1.5 SD)")
                        .sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.muted)
                }
                // Equatable: the ladder skips the 15 s updates unless its own walls, trades or ring changed.
                GammaLadder(v: v, week: compare ? v.week : nil, legs: trades ? legs : [], ring: router.gammaRing, today: home.today).equatable()
                GammaLegend()
            }
        }
        .padding(.horizontal, S.margin)
    }
}

// MARK: - Shared pieces

/// A white chip with a coloured dot (13h: Calmer regime, Drifting lower, Institution-heavy).
struct GammaChip: View {
    let text: String
    let dot: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(S.paper))
        .overlay(Capsule().strokeBorder(S.line, lineWidth: 1))
    }
}

/// A capsule segmented control drawn in the card's style (not Picker(.segmented): the labels are dates).
struct GammaSegments: View {
    let items: [(String, String)]
    let on: String
    let tap: (String) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { id, label in
                Button { if id != on { UISelectionFeedbackGenerator().selectionChanged(); tap(id) } } label: {
                    Text(label).sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(id == on ? S.ink : S.muted)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background { if id == on { Capsule().fill(S.paper).shadow(color: .black.opacity(0.08), radius: 2, y: 1) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(id == on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .background(Capsule().fill(S.track))
        .frame(minHeight: 36)
    }
}

/// The ladder's legend.
struct GammaLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(Capsule().fill(S.blue).frame(width: 16, height: 4), "Ceiling or Floor: price tends to stall")
            HStack(spacing: 8) {
                GammaStripes(color: S.orangeDeep).frame(width: 16, height: 4).clipShape(Capsule())
                Text("Accelerator: moves speed up").sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
                Capsule().fill(S.muted).frame(width: 16, height: 4).padding(.leading, 4)
                Text("Unclear").sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
            }
            Text("Bar: gamma at the wall").sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
            row(RoundedRectangle(cornerRadius: 3).strokeBorder(S.muted, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 16, height: 10),
                "A wall a week ago, the arrow shows where it moved")
            Text("●●● high · ●●○ medium · ●○○ low confidence, sell less")
                .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
        }
    }
    private func row(_ s: some View, _ t: String) -> some View {
        HStack(spacing: 8) { s; Text(t).sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted) }
    }
}

/// Words the Gamma tab shares.
enum GammaText {
    static func label(_ l: String) -> String {
        switch l { case "ceiling": "Ceiling"; case "floor": "Floor"; case "accelerator": "Accelerator"; default: "Unclear" }
    }
    static func icon(_ l: String, call: Bool) -> String {
        switch l {
        case "ceiling": "arrow.up.to.line.compact"
        case "floor": "arrow.down.to.line.compact"
        case "accelerator": call ? "chevron.up.2" : "chevron.down.2"
        default: "questionmark"
        }
    }
    static func dots(_ c: Int) -> String { String(repeating: "●", count: max(1, min(3, c))) + String(repeating: "○", count: 3 - max(1, min(3, c))) }
    static func conf(_ c: Int) -> String { c >= 3 ? "high" : c == 2 ? "medium" : "low" }
    /// "1st", "22nd", "73rd", "44th"
    static func ordinal(_ n: Int) -> String {
        let s = (n % 100 >= 11 && n % 100 <= 13) ? "th" : n % 10 == 1 ? "st" : n % 10 == 2 ? "nd" : n % 10 == 3 ? "rd" : "th"
        return "\(n)\(s)"
    }
    static func regime(_ r: String) -> String { r == "calmer" ? "Calmer regime" : r == "upside amplified" ? "Upside amplified" : "Downside amplified" }
    static func drift(_ p: Double) -> String { p > 1 ? "Drifting higher" : p < -1 ? "Drifting lower" : "Steady" }
    /// "0.2% below" / "1.4% above"
    static func vs(_ k: Double, _ spot: Double) -> String {
        String(format: "%.1f%% ", abs(k / spot - 1) * 100) + (k >= spot ? "above" : "below")
    }
    static func arrowPct(_ k: Double, _ spot: Double) -> String {
        (k >= spot ? "↑ " : "↓ ") + String(format: "%.1f%%", abs(k / spot - 1) * 100)
    }
    /// "as of Friday's close" / "as of today, live"
    static func asOf(_ day: String, today: String) -> String {
        day == today ? "as of today" : "as of \(fullWeekday(day))'s close"
    }
    static func fullWeekday(_ iso: String) -> String {
        ["Sun": "Sunday", "Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday", "Fri": "Friday", "Sat": "Saturday"][PWays.weekday(iso)] ?? "the last"
    }
    static func tradesLine(_ legs: [Leg]) -> String {
        let sold = legs.filter { $0.side == "sold" && $0.type == "call" }.reduce(0) { $0 + $1.n }
        let leaps = legs.filter { $0.side == "bought" && $0.type == "call" && !($0.up ?? false) }.reduce(0) { $0 + $1.n }
        let hedge = legs.filter { $0.side == "bought" && $0.type == "call" && ($0.up ?? false) }.reduce(0) { $0 + $1.n }
        let puts = legs.filter { $0.side == "bought" && $0.type == "put" }.reduce(0) { $0 + $1.n }
        return "\(sold) sold · \(leaps) LEAPS · \(hedge) hedges" + (puts > 0 ? " · \(puts) puts" : "") + " · breakevens"
    }
    static func money(_ v: Double) -> String { PWays.gamma(v) }
    /// A change in gamma without the dollar sign, as the design writes it: 0.6M · 85K.
    static func size(_ v: Double) -> String { v >= 1e5 ? String(format: "%.1fM", v / 1e6) : "\(Int((v / 1e3).rounded()))K" }
}
