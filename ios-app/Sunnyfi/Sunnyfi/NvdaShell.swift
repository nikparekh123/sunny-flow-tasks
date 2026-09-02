//
//  NvdaShell.swift
//  Sunnyfi — Ink rebuild · Events + Profile tabs
//
//  Faithful port of the design's EventsScreen (docs/ink-nvda-design) — a week
//  calendar strip over a day-grouped, expandable agenda. Profile is the
//  design's intentional stub ("not built in this prototype").
//
//  Event data below is the design's calendar model verbatim (the real
//  late-Jul → Aug 2026 macro + earnings slate incl. NVDA Q2 FY27). Swap for a
//  live macro_events / earnings_events feed later — the view is data-shaped.
//

import SwiftUI
import UIKit

// MARK: - Event model + data (design's calendar model)

struct NvEventStat: Identifiable, Hashable { let k: String; let v: String; var id: String { k } }
struct NvEvent: Identifiable, Hashable {
    let d: String              // ISO date "2026-08-26"
    let t: String              // "AMC" | "14:00" | "—"
    let cat: String            // Macro | Earnings | Corporate
    let weight: String         // high | med | low
    let title: String
    let line: String
    let note: String
    let mine: Bool
    let stats: [NvEventStat]
    var id: String { d + t + title }
    init(_ d: String, _ t: String, _ cat: String, _ weight: String, _ title: String, _ line: String,
         _ note: String, mine: Bool = false, _ stats: [(String, String)]) {
        self.d = d; self.t = t; self.cat = cat; self.weight = weight; self.title = title
        self.line = line; self.note = note; self.mine = mine
        self.stats = stats.map { NvEventStat(k: $0.0, v: $0.1) }
    }
}

enum NvEvents {
    static let all: [NvEvent] = [
        .init("2026-07-27", "AMC", "Earnings", "med", "Tesla · Q2 results", "Peer tape · after the close",
              "First of the megacap prints. Moves the AI complex overnight and sets the tone into the Fed on Wednesday.",
              [("Est. EPS", "$0.61"), ("Implied move", "±7.4%"), ("Your exposure", "Indirect")]),
        .init("2026-07-28", "10:00", "Macro", "low", "Consumer confidence", "July · Conference Board",
              "Second-order for semis. Watched only for how it colours the Fed statement a day later.",
              [("Prior", "97.2"), ("Consensus", "96.0"), ("Impact", "Low")]),
        .init("2026-07-28", "—", "Macro", "low", "FOMC meeting begins", "Day one of two · no release",
              "No statement today. Positioning ahead of Wednesday usually lifts implied vol into the close.",
              [("Decision", "Jul 29"), ("Priced cut", "68%"), ("Impact", "Low")]),
        .init("2026-07-29", "14:00", "Macro", "high", "FOMC rate decision", "Statement · 25bp cut priced at 68%",
              "The one macro print that repriced NVDA more than 2% in each of the last three meetings. Your Oct and Jan puts carry the downside; the near calls are already sold by then.",
              [("Priced cut", "68%"), ("Last 3 moves", "±2.4%"), ("Your delta", "3,914")]),
        .init("2026-07-29", "14:30", "Macro", "med", "Powell press conference", "Thirty minutes after the statement",
              "The tape usually reverses the knee-jerk move somewhere in the first ten minutes of questions.",
              [("Duration", "~45 min"), ("Vol window", "14:30–15:10"), ("Impact", "Med")]),
        .init("2026-07-29", "AMC", "Earnings", "high", "Microsoft · Q4 results", "Azure capex is the NVDA read",
              "Capex guidance is the cleanest public proxy for next-year datacentre GPU demand. NVDA has traded with MSFT's capex line six prints running.",
              [("Est. EPS", "$3.62"), ("Capex est.", "$24B"), ("NVDA beta", "0.71")]),
        .init("2026-07-29", "AMC", "Earnings", "med", "Meta · Q2 results", "Second capex read of the week",
              "Confirms or contradicts the Microsoft capex signal an hour later.",
              [("Est. EPS", "$6.71"), ("Implied move", "±6.1%"), ("NVDA beta", "0.54")]),
        .init("2026-07-30", "08:30", "Macro", "med", "GDP · advance Q2", "First estimate",
              "Rarely moves semis on its own, but a hot print undoes the September cut the market has half-priced.",
              [("Prior", "2.1%"), ("Consensus", "1.8%"), ("Impact", "Med")]),
        .init("2026-07-30", "AMC", "Earnings", "med", "Apple · Q3 results", "Peer tape · after the close",
              "Least correlated of the megacap prints for your book. Watched for overall risk appetite only.",
              [("Est. EPS", "$1.42"), ("Implied move", "±4.2%"), ("NVDA beta", "0.31")]),
        .init("2026-07-30", "AMC", "Earnings", "med", "Amazon · Q2 results", "AWS capex · third read",
              "Third and last capex read of the week. Three matching lines make a trend the market will trade into NVDA's own print.",
              [("Est. EPS", "$1.28"), ("Capex est.", "$26B"), ("NVDA beta", "0.63")]),
        .init("2026-07-31", "08:30", "Macro", "high", "PCE price index", "The Fed's preferred inflation gauge",
              "Two days after the decision, this is the print that either validates the cut path or takes it back.",
              [("Prior core", "2.6%"), ("Consensus", "2.5%"), ("Impact", "High")]),
        .init("2026-08-03", "10:00", "Macro", "low", "ISM manufacturing", "July",
              "Cyclical read. Semis follow it loosely at the index level, not at the single-name level.",
              [("Prior", "48.9"), ("Consensus", "49.4"), ("Impact", "Low")]),
        .init("2026-08-05", "08:15", "Macro", "low", "ADP employment", "Private payrolls · July",
              "A warm-up for Friday's payrolls. Moves rates more than it moves semis.",
              [("Prior", "104k"), ("Consensus", "112k"), ("Impact", "Low")]),
        .init("2026-08-07", "08:30", "Macro", "high", "Nonfarm payrolls", "July · the first post-Fed labour print",
              "Largest single-print vol event of the month outside CPI. Long-dated puts hold their value through it; short premium does not.",
              [("Prior", "147k"), ("Consensus", "120k"), ("Impact", "High")]),
        .init("2026-08-12", "08:30", "Macro", "high", "CPI · July", "Headline and core",
              "The other half of the inflation picture. Sets the September meeting before NVDA reports.",
              [("Prior core", "3.0%"), ("Consensus", "2.9%"), ("Impact", "High")]),
        .init("2026-08-19", "—", "Corporate", "med", "NVDA ex-dividend", "$0.01 a share · 5,001 sh",
              "Token dividend, but it prices into the calls you sell. Fifty dollars, and a one-cent drop in the reference price at the open.",
              mine: true, [("Per share", "$0.01"), ("Your shares", "5,001"), ("Cash", "$50")]),
        .init("2026-08-26", "AMC", "Earnings", "high", "NVIDIA · Q2 FY27 results", "The print the whole book is positioned around",
              "Implied move is ±8.1%, worth roughly $85k on the share sleeve alone. The Oct and Jan puts are the floor through it; the weeklies you keep selling should stop before the week of.",
              mine: true, [("Implied move", "±8.1%"), ("Share risk", "±$85k"), ("Puts held", "44 ct")]),
        .init("2026-08-27", "09:30", "Earnings", "med", "Post-earnings open", "Vol crush · sell-side revisions land",
              "Implied vol collapses at the open. If the weeklies are back on by then, this is the session that pays for the week.",
              mine: true, [("IV before", "48%"), ("IV after", "~31%")]),
    ]
}

// MARK: - Events tab (faithful port of EventsScreen)

struct NvdaEventsScreen: View {
    private static let dayL = ["S", "M", "T", "W", "T", "F", "S"]
    private static let mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let wd = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }

    private let today: Date
    private let todayISO: String
    @State private var sel: String
    @State private var wk = 0
    @State private var filter = "All"
    @State private var open: String?

    init() {
        let c = Self.cal
        let t = c.startOfDay(for: Date())
        today = t
        let iso = Self.isoStr(t)
        todayISO = iso
        _sel = State(initialValue: iso)
        _open = State(initialValue: iso + "|0")
    }

    private static func isoStr(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    private func toDate(_ iso: String) -> Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return today }
        return Self.cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) ?? today
    }
    private func addDays(_ d: Date, _ n: Int) -> Date { Self.cal.date(byAdding: .day, value: n, to: d)! }
    private func weekdayIdx(_ d: Date) -> Int { Self.cal.component(.weekday, from: d) - 1 }
    private func dayNum(_ d: Date) -> Int { Self.cal.component(.day, from: d) }
    private func monthIdx(_ d: Date) -> Int { Self.cal.component(.month, from: d) - 1 }
    private func yearNum(_ d: Date) -> Int { Self.cal.component(.year, from: d) }

    private func pass(_ e: NvEvent) -> Bool { filter == "All" || e.cat == filter }
    private var byDay: [String: [NvEvent]] {
        var m: [String: [NvEvent]] = [:]
        for e in NvEvents.all where pass(e) { m[e.d, default: []].append(e) }
        return m
    }

    var body: some View {
        let sun = addDays(today, -weekdayIdx(today) + wk * 7)
        let week = (0..<7).map { addDays(sun, $0) }
        let by = byDay
        let days = agendaDays(by)
        return VStack(spacing: 0) {
            head(week)
            weekStrip(week, by)
            filters
            ScrollView {
                if days.isEmpty {
                    quiet
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.element) { di, iso in
                            section(iso, by[iso] ?? [], showOnward: di == 0 && days.count > 1)
                                .inkEntrance(min(di, 4))
                        }
                        Color.clear.frame(height: 104)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // ── header ──
    private func head(_ week: [Date]) -> some View {
        let a = week[0], b = week[6]
        let label = monthIdx(a) == monthIdx(b)
            ? "\(Self.mon[monthIdx(a)]) \(yearNum(a))"
            : "\(Self.mon[monthIdx(a)]) — \(Self.mon[monthIdx(b)]) \(yearNum(b))"
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Upcoming").font(InkFont.serif(29)).tracking(29 * -0.01).foregroundStyle(Ink.text)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                navBtn("chevron.left") { wk -= 1 }
                Text(label.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.16).foregroundStyle(Ink.dim)
                navBtn("chevron.right") { wk += 1 }
            }
            .fixedSize()
        }
        .padding(EdgeInsets(top: 24, leading: 16, bottom: 16, trailing: 16))
    }
    private func navBtn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .regular)).foregroundStyle(Ink.text)
                .frame(width: 26, height: 26)
                .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(Ink.hair, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // ── week strip ──
    private func weekStrip(_ week: [Date], _ by: [String: [NvEvent]]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(week.enumerated()), id: \.offset) { i, d in
                let iso = Self.isoStr(d)
                let on = iso == sel
                let isToday = iso == todayISO
                let list = by[iso] ?? []
                let past = d < today
                Button {
                    sel = iso; open = nil
                } label: {
                    VStack(spacing: 9) {
                        Text(Self.dayL[i]).font(InkFont.mono(9)).tracking(9 * 0.1)
                            .foregroundStyle(on ? Ink.text : Ink.dim)
                        Text("\(dayNum(d))").font(InkFont.mono(14)).tracking(14 * -0.02)
                            .foregroundStyle(on ? Ink.invertText : Ink.text)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(on ? Ink.invertBg : .clear))
                            .overlay { if !on && isToday { Circle().strokeBorder(Ink.dim, lineWidth: 1) } }
                        marks(list, on: on)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .inkRelevance(past && !on ? .r3 : .r1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(EdgeInsets(top: 2, leading: 10, bottom: 14, trailing: 10))
    }
    private func marks(_ list: [NvEvent], on: Bool) -> some View {
        let color = on ? Ink.text : Ink.dim
        return HStack(spacing: 3) {
            ForEach(Array(list.prefix(3).enumerated()), id: \.offset) { _, e in
                Circle().fill(e.mine ? color : .clear)
                    .overlay { if !e.mine { Circle().strokeBorder(color.opacity(0.6), lineWidth: 1) } }
                    .frame(width: 4, height: 4)
            }
            if list.count > 3 { Text("+").font(InkFont.mono(7)).foregroundStyle(color) }
        }
        .frame(height: 7)
    }

    // ── filters ──
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(["All", "Macro", "Earnings", "Corporate"], id: \.self) { f in
                    Button { filter = f; open = nil } label: { chip(f, on: filter == f) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hair).frame(height: 1) }
    }
    private func chip(_ text: String, on: Bool) -> some View {
        Text(text.uppercased()).font(InkFont.mono(9.5, .medium)).tracking(9.5 * 0.14)
            .foregroundStyle(on ? Ink.invertText : Ink.dim)
            .padding(.horizontal, 12).frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: Ink.radiusElement).fill(on ? Ink.invertBg : .clear))
            .overlay(RoundedRectangle(cornerRadius: Ink.radiusElement).strokeBorder(on ? .clear : Ink.hair, lineWidth: 1))
    }

    // ── agenda ──
    private func agendaDays(_ by: [String: [NvEvent]]) -> [String] {
        var out: [String] = []
        let start = toDate(sel)
        var i = 0
        while i < 45 && out.count < 8 {
            let iso = Self.isoStr(addDays(start, i))
            if by[iso] != nil { out.append(iso) }
            i += 1
        }
        return out
    }
    private func label(_ iso: String) -> String {
        let diff = Self.cal.dateComponents([.day], from: today, to: toDate(iso)).day ?? 0
        if diff == 0 { return "Today" }
        if diff == 1 { return "Tomorrow" }
        if diff == -1 { return "Yesterday" }
        return Self.wd[weekdayIdx(toDate(iso))]
    }
    private func stamp(_ iso: String) -> String {
        let d = toDate(iso)
        return "\(Self.dayL[weekdayIdx(d)]) \(dayNum(d)) \(Self.mon[monthIdx(d)])"
    }

    private func section(_ iso: String, _ list: [NvEvent], showOnward: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Text(label(iso)).font(InkFont.serif(24)).tracking(24 * -0.01).foregroundStyle(Ink.text)
                Text("\(stamp(iso)) · \(list.count) \(list.count == 1 ? "event" : "events")".uppercased())
                    .font(InkFont.mono(9.5)).tracking(9.5 * 0.16).foregroundStyle(Ink.dim)
            }
            .padding(EdgeInsets(top: 22, leading: 16, bottom: 14, trailing: 16))
            ForEach(Array(list.enumerated()), id: \.offset) { i, e in
                let key = iso + "|\(i)"
                EventRowView(e: e, isOpen: open == key, past: toDate(iso) < today) {
                    open = (open == key) ? nil : key
                }
            }
            if showOnward {
                HStack(spacing: 12) {
                    Text("Onward").font(InkFont.mono(9)).tracking(9 * 0.18).foregroundStyle(Ink.dim)
                    Rectangle().fill(Ink.hair).frame(height: 1)
                }
                .padding(EdgeInsets(top: 24, leading: 16, bottom: 0, trailing: 16))
            }
        }
    }

    private var quiet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing scheduled".uppercased()).font(InkFont.mono(10)).tracking(10 * 0.16).foregroundStyle(Ink.dim)
            Text("No \(filter == "All" ? "" : filter.lowercased() + " ")events from \(stamp(sel)) onward.")
                .font(InkFont.display(13, .light)).foregroundStyle(Ink.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(EdgeInsets(top: 40, leading: 16, bottom: 40, trailing: 16))
    }
}

private struct EventRowView: View {
    let e: NvEvent
    let isOpen: Bool
    let past: Bool
    let onToggle: () -> Void

    var body: some View {
        let rank: InkRelevance = past ? .r3 : (e.weight == "low" ? .r2 : .r1)
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 14) {
                Text(e.t).font(InkFont.mono(11)).tracking(11 * 0.04).foregroundStyle(Ink.text)
                    .frame(width: 46, alignment: .leading).padding(.top, 2)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(e.title).font(InkFont.display(14.5, .regular)).foregroundStyle(Ink.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if e.weight == "high" {
                            Text("Moves").font(InkFont.mono(8)).tracking(8 * 0.14).foregroundStyle(Ink.text)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .overlay(Capsule().strokeBorder(Ink.dim, lineWidth: 1))
                        }
                    }
                    Text("\(e.cat) · \(e.line)".uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.1)
                        .foregroundStyle(Ink.dim).padding(.top, 8).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if isOpen {
                        Text(e.note).font(InkFont.display(12.5, .light)).foregroundStyle(Ink.dim)
                            .lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(e.stats.enumerated()), id: \.element.id) { i, s in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(s.k.uppercased()).font(InkFont.mono(8)).tracking(8 * 0.12)
                                        .foregroundStyle(Ink.dim).lineLimit(1)
                                    Text(s.v).font(InkFont.mono(14)).tracking(14 * -0.02).foregroundStyle(Ink.text)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, i == 0 ? 0 : 10).padding(.trailing, 10)
                                .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Ink.hair).frame(width: 1) } }
                            }
                        }
                        .padding(.top, 14).overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .regular)).foregroundStyle(Ink.dim)
                    .rotationEffect(.degrees(isOpen ? 90 : 0)).padding(.top, 3)
            }
            .padding(EdgeInsets(top: 16, leading: 12, bottom: 16, trailing: 16))
            .overlay(alignment: .leading) { Rectangle().fill(e.mine ? Ink.text : .clear).frame(width: 2) }
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hair).frame(height: 1) }
        .inkRelevance(rank)
        .animation(InkMotion.fast, value: isOpen)
    }
}

// MARK: - Profile tab (functional; Ink-styled, no Claude Design mockup yet)

struct NvdaProfileScreen: View {
    @State private var redesign = RedesignSession.shared
    let auth: AuthStore
    let lock: AppLock
    let prefs: NotificationPrefs
    private let appPrefs = AppPrefs.shared
    @State private var showSignOut = false

    private var email: String {
        if case .signedIn(let e) = auth.state { return e }
        return "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                InkSectionHead(title: "Account", count: "sunnyfi")
                header.padding(.horizontal, 16)
                display
                security
                account
                version
                Color.clear.frame(height: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog("Sign out of Sunnyfi?", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await auth.signOut(); lock.onboardingDone = false } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You'll need the 10-digit code to sign back in.") }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("NP").font(InkFont.mono(20, .medium)).foregroundStyle(Ink.invertText)
                .frame(width: 60, height: 60).background(Circle().fill(Ink.invertBg))
            VStack(alignment: .leading, spacing: 5) {
                Text("Niket Parekh").font(InkFont.serif(20)).foregroundStyle(Ink.text)
                Text(email).font(InkFont.mono(11)).foregroundStyle(Ink.dim)
            }
            Spacer(minLength: 0)
        }
    }

    private var display: some View {
        panel("Display") {
            row(icon: "circle.lefthalf.filled", label: "Appearance") {
                InkSegment()
            }
            hair
            toggleRow(icon: "eye.slash", label: "Hide P&L amounts",
                      on: Binding(get: { appPrefs.hidePnL }, set: { appPrefs.hidePnL = $0 }))
            hair
            /* ⚠ PERSISTED as of 2026-09-02, when the paged shell became the
               default. This row is now the way FORWARD after an escape, so it
               must clear the escape flag rather than only set the in-memory
               one, or the next launch undoes it. */
            toggleRow(icon: "square.grid.2x2", label: "Use new design",
                      on: Binding(get: { redesign.on },
                                  set: { $0 ? redesign.useNewShell() : redesign.useCurrentApp() }))
        }
    }

    private var security: some View {
        panel("Security") {
            toggleRow(icon: lock.biometricKind.icon, label: lock.biometricKind.label,
                      on: Binding(get: { lock.biometricEnabled }, set: { newVal in
                          Task {
                              if newVal { if await lock.authenticate(reason: "Enable lock") { lock.biometricEnabled = true } }
                              else { lock.biometricEnabled = false }
                          }
                      }))
            hair
            toggleRow(icon: "icloud.and.arrow.down", label: "Background refresh",
                      on: Binding(get: { appPrefs.backgroundRefresh }, set: { appPrefs.backgroundRefresh = $0 }))
        }
    }

    private var account: some View {
        panel("Account & data") {
            Link(destination: URL(string: "https://nikparekh123.github.io/sunny-flow-tasks/privacy")!) {
                rowBody(icon: "lock.shield", label: "Privacy & data", tint: Ink.text) {
                    Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Ink.dim)
                }
            }.buttonStyle(.plain)
            hair
            Link(destination: URL(string: "mailto:support@sunnyfi.co")!) {
                rowBody(icon: "envelope", label: "Help & support", tint: Ink.text) {
                    Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Ink.dim)
                }
            }.buttonStyle(.plain)
            hair
            Button(role: .destructive) { showSignOut = true } label: {
                rowBody(icon: "rectangle.portrait.and.arrow.right", label: "Sign out", tint: Ink.loss) { EmptyView() }
            }.buttonStyle(.plain)
        }
    }

    private var version: some View {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return HStack {
            Spacer()
            Text("Sunnyfi v\(v) · build \(b)").font(InkFont.mono(10)).tracking(10 * 0.06).foregroundStyle(Ink.dim)
            Spacer()
        }
    }

    @ViewBuilder private func panel<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(InkFont.mono(9.5)).tracking(9.5 * 0.16).foregroundStyle(Ink.dim).padding(.leading, 20)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).fill(Ink.surface))
                .overlay(RoundedRectangle(cornerRadius: Ink.radiusCard, style: .continuous).strokeBorder(Ink.hair, lineWidth: 1))
                .padding(.horizontal, 16)
        }
    }
    private var hair: some View { Rectangle().fill(Ink.hair).frame(height: 1).padding(.leading, 54) }
    @ViewBuilder private func row<T: View>(icon: String, label: String, @ViewBuilder trailing: () -> T) -> some View {
        rowBody(icon: icon, label: label, tint: Ink.text, trailing: trailing)
    }
    @ViewBuilder private func toggleRow(icon: String, label: String, on: Binding<Bool>) -> some View {
        rowBody(icon: icon, label: label, tint: Ink.text) { Toggle("", isOn: on).labelsHidden().tint(Ink.invertBg) }
    }
    @ViewBuilder private func rowBody<T: View>(icon: String, label: String, tint: Color, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13, weight: .regular)).foregroundStyle(tint)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(Ink.text.opacity(0.06)))
            Text(label).font(InkFont.display(14, .regular)).foregroundStyle(tint)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
    }
}

private struct InkSegment: View {
    @Namespace private var ns
    var body: some View {
        let prefs = AppPrefs.shared
        let sel = prefs.appearance          // stored @Observable → tracked, so the thumb re-renders
        return HStack(spacing: 0) {
            ForEach(AppPrefs.Appearance.allCases) { a in
                let on = a == sel
                Button { prefs.appearance = a } label: {
                    Text(a.rawValue.uppercased()).font(InkFont.mono(9.5, .medium)).tracking(9.5 * 0.1)
                        .foregroundStyle(on ? Ink.invertText : Ink.dim)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background {
                            if on { Capsule().fill(Ink.invertBg).matchedGeometryEffect(id: "segThumb", in: ns) }
                        }
                }.buttonStyle(.plain)
            }
        }
        .frame(width: 186)
        .padding(2).background(Capsule().fill(Ink.text.opacity(0.06)))
        .animation(InkMotion.fast, value: sel)
    }
}
