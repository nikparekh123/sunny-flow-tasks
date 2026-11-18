//
//  Activity.swift
//  Sunny
//
//  Activity, the notification center (handoff 2026-11-18, round 161a + 161c; Nik, 16 Nov 2026): what happened, when,
//  in order; Home keeps where things stand. sunny-home writes the events (activity.ts) and sends the last eight days
//  in payload.activity with the IBKR sync state and the Levels card's figures.
//    The bell: top right on Home and Positions, subtle (no glass, the muted grey, a 1.8 stroke); a small red dot when
//    something is unread, a red ! when IBKR stops. Hidden on Overview, Search and a ticker chart.
//    The page slides in from the right: the sync line, All · IBKR · Levels · Moves, Today / Yesterday / Earlier this
//    week, Mark all read. A pickup opens to its trades; a level or move opens Positions on that name.
//    The Levels card (Home, 2 · Your book, every moment): what crossed a line, then every name by average and by wall.
//  Read state is this phone's (UserDefaults), per book. No em dashes in any words here.
//

import SwiftUI

@Observable
final class ActivityRead {
    static let shared = ActivityRead()
    private(set) var read: [String: Set<String>] = [:]
    func keys(_ book: String) -> Set<String> {
        if let r = read[book] { return r }
        let r = Set(UserDefaults.standard.stringArray(forKey: "activity.read.\(book)") ?? [])
        read[book] = r
        return r
    }
    func mark(_ book: String, _ ks: [String]) {
        var r = keys(book); r.formUnion(ks)
        read[book] = r
        UserDefaults.standard.set(Array(r.suffix(400)), forKey: "activity.read.\(book)")
    }
}

enum ActivityWords {
    static func clock(_ iso: String?) -> String {
        guard let iso, let d = SXClient.parseDate(iso) else { return "" }
        let f = DateFormatter(); f.timeZone = MarketClock.ny; f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
    /// "Today", "Yesterday", "Earlier this week" from an event's day.
    static func group(_ day: String, today: String) -> Int {
        if day == today { return 0 }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        guard let a = f.date(from: today), let b = f.date(from: day) else { return 2 }
        let d = Int((a.timeIntervalSince(b) / 86400).rounded())
        return d <= 1 || (d <= 3 && Calendar.current.component(.weekday, from: a) == 2) ? 1 : 2
    }
}

/// The bell (161a): a red dot for unread, a red ! when IBKR stops; VoiceOver reads the count.
struct ActivityBell: View {
    let activity: JSONValue?
    let book: String
    let open: () -> Void
    @State private var reads = ActivityRead.shared
    var body: some View {
        let evs = activity?["events"].array ?? []
        let unread = evs.filter { !reads.keys(book).contains($0["key"].string ?? "") }.count
        let stopped = activity?["sync"]["stopped"].bool ?? false
        Button(action: open) {
            Image(systemName: "bell").font(.system(size: 18, weight: .regular)).foregroundStyle(S.secondary)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if stopped {
                        Text("!").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 14, height: 14).background(Circle().fill(S.red)).offset(x: -8, y: 9)
                    } else if unread > 0 {
                        Circle().fill(S.red).frame(width: 7, height: 7).offset(x: -12, y: 12)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stopped ? "Activity, IBKR has stopped" : unread > 0 ? "Activity, \(unread) unread" : "Activity")
    }
}

/// The bell in place: top right in the strip's row on Home and Positions (2 pt under the safe area, 6 from the edge,
/// so its 20 pt glyph sits 14 + 12 from the side as drawn). Nothing until the server sends activity.
struct ActivityBellSlot: View {
    @Environment(BriefState.self) private var brief
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        if brief.activity != nil {
            ActivityBell(activity: brief.activity, book: brief.book ?? "S") {
                withAnimation(reduce ? nil : S.standard(0.45)) { brief.activityOpen = true }
            }
            .padding(.top, 2).padding(.trailing, 6)
        }
    }
}

/// The Activity page (161a), from the right, with a back button.
struct ActivityPage: View {
    let activity: JSONValue?
    let book: String
    let today: String
    let close: () -> Void
    let openName: (String) -> Void
    @State private var reads = ActivityRead.shared
    @State private var filter = "all"
    @State private var openKeys: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduce

    private static let filters = [("all", "All"), ("ibkr", "IBKR"), ("lvl", "Levels"), ("move", "Moves")]

    var body: some View {
        let evs = (activity?["events"].array ?? []).filter { filter == "all" || $0["kind"].string == filter }
        let sync = activity?["sync"]
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: close) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(S.ink)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Back")
                Spacer()
                Button {
                    reads.mark(book, (activity?["events"].array ?? []).compactMap { $0["key"].string })
                } label: {
                    Text("Mark all read").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        .frame(minHeight: 44).padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Activity").sType(SType(size: 34, weight: 700, line: 40, tracking: -0.03), tabular: false).foregroundStyle(S.ink)
                        .accessibilityAddTraits(.isHeader)
                    // IBKR first: when it last synced, or red when it stopped.
                    HStack(spacing: 8) {
                        Circle().fill((sync?["stopped"].bool ?? false) ? S.red : S.green).frame(width: 8, height: 8)
                        Text((sync?["stopped"].bool ?? false) ? "No data from IBKR since \(ActivityWords.clock(sync?["at"].string))" : "IBKR synced \(ActivityWords.clock(sync?["at"].string))")
                            .sType(SType(size: 14, weight: 600, line: 19, tracking: 0), tabular: true)
                            .foregroundStyle((sync?["stopped"].bool ?? false) ? S.red : S.secondary)
                    }
                    HStack(spacing: 6) {
                        ForEach(Self.filters, id: \.0) { k, l in
                            let on = filter == k
                            Button { withAnimation(S.moving(.easeOut(duration: 0.2), reduce)) { filter = k } } label: {
                                Text(l).sType(SType(size: 14, weight: on ? 700 : 500, line: 18, tracking: 0), tabular: false)
                                    .foregroundStyle(on ? S.ink : S.secondary)
                                    .padding(.horizontal, 12).frame(minHeight: 32)
                                    .background(on ? S.dynA(0x767680, 0.12, 0x767680, 0.24) : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                        }
                    }
                    if evs.isEmpty {
                        Text("Nothing yet.").sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    }
                    ForEach([0, 1, 2], id: \.self) { g in
                        let items = evs.filter { ActivityWords.group($0["day"].string ?? "", today: today) == g }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(["Today", "Yesterday", "Earlier this week"][g]).sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false)
                                    .foregroundStyle(S.secondary).padding(.bottom, 6)
                                ForEach(Array(items.enumerated()), id: \.offset) { _, e in row(e) }
                            }
                        }
                    }
                }
                .padding(.horizontal, S.margin).padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .background(SBackground().ignoresSafeArea())
    }

    private func row(_ e: JSONValue) -> some View {
        let key = e["key"].string ?? "", unread = !reads.keys(book).contains(key)
        let trades = e["data"]["trades"].array, isOpen = openKeys.contains(key), t = e["t"].string
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                reads.mark(book, [key])
                if !trades.isEmpty {
                    withAnimation(S.moving(.easeOut(duration: 0.25), reduce) ?? .linear(duration: 0)) { if isOpen { openKeys.remove(key) } else { openKeys.insert(key) } }
                } else if let t { openName(t) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(unread ? S.blue : .clear).frame(width: 7, height: 7).padding(.top, 13)
                    if let t { BLogo(ticker: t, size: 32) }
                    else {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 28)).foregroundStyle(S.secondary).frame(width: 32, height: 32)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(e["title"].string ?? "").sType(SType(size: 16, weight: 600, line: 21, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            Spacer(minLength: 8)
                            Text(ActivityWords.clock(e["at"].string)).sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.secondary)
                        }
                        if let b = e["body"].string, !b.isEmpty {
                            Text(b).sType(SType(size: 14, weight: 500, line: 19, tracking: 0), tabular: false).foregroundStyle(S.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(!trades.isEmpty ? (isOpen ? "Hides the trades" : "Shows the trades") : t != nil ? "Opens it on Positions" : "")
            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(trades.enumerated()), id: \.offset) { _, x in
                        HStack(alignment: .top, spacing: 10) {
                            BLogo(ticker: x["t"].string, size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(x["what"].string ?? "").sType(SType(size: 14, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                Text(x["at"].string ?? "").sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.secondary)
                            }
                            Spacer(minLength: 8)
                            Text("Added").sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.green)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.leading, 51).padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
    }
}

/// The Levels card's host: the live activity and the opener from BriefState (Home's 30 s payload, not the words one).
struct LevelsCardHost: View {
    let card: JSONValue
    @Environment(BriefState.self) private var brief
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        LevelsCard(card: card, activity: brief.activity, today: brief.today) {
            withAnimation(reduce ? nil : S.standard(0.45)) { brief.activityOpen = true }
        }
    }
}

/// The Levels card (161c) on Home, in 2 · Your book: what crossed a line (today, yesterday before the bell, this week on
/// the weekend), then every name by its averages and this week's walls, folded. A row opens Activity.
struct LevelsCard: View {
    let card: JSONValue
    let activity: JSONValue?
    let today: String
    let openActivity: () -> Void
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let when = card["when"].string ?? "today"
        let lv = activity?["levels"].array ?? []
        let evs = (activity?["events"].array ?? []).filter { $0["kind"].string == "lvl" || $0["kind"].string == "move" }
            .filter { e in let g = ActivityWords.group(e["day"].string ?? "", today: today); return when == "today" ? g == 0 : when == "yday" ? g == 1 : g <= 2 }
        let crossers = Array(Dictionary(grouping: evs, by: { $0["t"].string ?? "" }).values.compactMap { $0.first })
            .sorted { ($0["at"].string ?? "") > ($1["at"].string ?? "") }
        let under3 = lv.filter { $0["ma"].string == "000" }.compactMap { $0["name"].string }
        let label = when == "yday" ? "yesterday" : when == "week" ? "this week" : "today"
        VStack(alignment: .leading, spacing: 10) {
            (Text(crossers.isEmpty ? "No name crossed a line \(label)." : "\(crossers.count) \(crossers.count == 1 ? "name" : "names") crossed a line \(label).").fontWeight(.semibold)
             + Text(under3.isEmpty ? "" : " \(Self.list(under3)) \(under3.count == 1 ? "is" : "are") under all three averages."))
                .sType(SType(size: 17, weight: 400, line: 23, tracking: 0)).foregroundStyle(S.ink)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(crossers.enumerated()), id: \.offset) { _, e in
                let t = e["t"].string ?? "", l = lv.first { $0["t"].string == t }
                Button(action: openActivity) {
                    HStack(spacing: 10) {
                        BLogo(ticker: t, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l?["name"].string ?? t).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            Text("\(Self.what(e)) · \(ActivityWords.clock(e["at"].string))").sType(SType(size: 13, weight: 500, line: 17, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                        }
                        Spacer(minLength: 8)
                        if let l {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(String(format: "$%.2f", l["px"].double ?? 0)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(S.ink)
                                let mv = l["mv"].double ?? 0
                                Text("\(mv < 0 ? "▼" : "▲") \(String(format: "%.1f", abs(mv)))%").sType(SType(size: 12, weight: 600, line: 16, tracking: 0)).foregroundStyle(mv < 0 ? S.red : S.green)
                            }
                        }
                    }
                    .padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Activity")
            }
            Button { withAnimation(S.moving(.easeOut(duration: 0.25), reduce) ?? .linear(duration: 0)) { open.toggle() } } label: {
                HStack {
                    Text("Every name").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text("\(lv.count) names").sType(SType(size: 13, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(S.secondary).rotationEffect(.degrees(open ? 90 : 0))
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
            if open {
                VStack(alignment: .leading, spacing: 12) {
                    block("Against the 20, 50 and 200-day", groups: [("111", "Over all three averages"), ("011", "Under the 20-day"), ("001", "Under the 20 and 50-day"),
                        ("100", "Over the 20-day, under the 50 and 200"), ("110", "Under the 200-day"), ("101", "Under the 50-day"), ("010", "Over the 50-day only"), ("000", "Under all three")],
                          pick: { $0["ma"].string ?? "" }, lv: lv, chip: { _ in "" })
                    block("Against this week’s walls", groups: [("c", "Near a ceiling"), ("f", "Near a floor"), ("b", "Between the walls")],
                          pick: { $0["wall"].string ?? "b" }, lv: lv, chip: { l in l["wallK"].double.map { String(format: "%g", $0) } ?? "" })
                }
                .transition(.opacity)
            }
        }
        .briefCard()
        .padding(.horizontal, S.margin)
    }

    private func block(_ h: String, groups: [(String, String)], pick: @escaping (JSONValue) -> String, lv: [JSONValue], chip: @escaping (JSONValue) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(h).sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary)
            ForEach(groups, id: \.0) { k, l in
                let names = lv.filter { pick($0) == k }
                if !names.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l).sType(SType(size: 14, weight: 500, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        SXFlow(spacing: 8) {
                            ForEach(Array(names.enumerated()), id: \.offset) { _, n in
                                HStack(spacing: 4) {
                                    BLogo(ticker: n["t"].string, size: 20)
                                    Text(n["t"].string ?? "").sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                    let c = chip(n)
                                    if !c.isEmpty { Text(c).sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.secondary) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// "Over its 20-day", "Near the 74 ceiling", "Up 6.2%" (the event's title without the name).
    static func what(_ e: JSONValue) -> String {
        let t = e["title"].string ?? ""
        guard let sp = t.range(of: " ") else { return t }
        let rest = String(t[sp.upperBound...])
        // Names are one word (Nike, Alibaba, Lululemon, Netflix, Uber, FIS, Nvidia); a two-word name keeps its second word.
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }
    static func list(_ xs: [String]) -> String { xs.count <= 1 ? xs.joined() : xs.dropLast().joined(separator: ", ") + " and " + (xs.last ?? "") }
}
