//
//  SunnyWalls.swift
//  Sunny
//
//  Block 13d (handoff 31, 23 Oct 2026) · the Walls screen, pushed from All
//  walls on a Position card. For each expiry through March: the two biggest
//  call walls above the price and put walls below, the change since the day
//  before, the flip, the sleeping wall, the week at the close and every strike
//  on demand. Read straight from gex_walls (one row per expiry per close,
//  written by gex-walls after the close); nothing here is worked out on the
//  phone except the day-to-day changes.
//

import SwiftUI
import Supabase

/// One expiry's walls at one close (gex_walls, `expiry` set).
struct WallDay: Decodable, Hashable {
    let ticker: String?
    let day: String
    let expiry: String
    let spot: Double
    let flip: Double?
    let callWall: Double?
    let callWallGex: Double?
    let callWall2: Double?
    let callWall2Gex: Double?
    let putWall: Double?
    let putWallGex: Double?
    let putWall2: Double?
    let putWall2Gex: Double?
    let sleep: Sleep?
    let strikes: [Strike]?
    struct Sleep: Decodable, Hashable {
        let call: Side?
        let put: Side?
        struct Side: Decodable, Hashable { let k: Double; let oi: Double }
    }
    struct Strike: Decodable, Hashable {
        let k: Double
        let call: Double
        let put: Double
        let oi: Double
    }
    /// Call 1st, Call 2nd, Put 1st, Put 2nd: (strike, gamma).
    var walls: [(k: Double?, g: Double?)] {
        [(callWall, callWallGex), (callWall2, callWall2Gex), (putWall, putWallGex), (putWall2, putWall2Gex)]
    }
}

enum WallsData {
    /// The last ten days of rows for a name (two weeks of closes at most), oldest first. A DEBUG simulator
    /// run with `-wallsFixture <path>` reads a saved copy instead (the same JSON array).
    @MainActor static func load(_ t: String, today: String) async throws -> [WallDay] {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        #if DEBUG && targetEnvironment(simulator)
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-wallsFixture"), i + 1 < a.count {
            return try d.decode([WallDay].self, from: Data(contentsOf: URL(fileURLWithPath: a[i + 1]))).filter { $0.ticker == t }
        }
        #endif
        let since = WallsData.addDays(today, -10)
        let res = try await SupabaseService.client.from("gex_walls")
            .select("ticker,day,expiry,spot,flip,call_wall,call_wall_gex,call_wall2,call_wall2_gex,put_wall,put_wall_gex,put_wall2,put_wall2_gex,sleep,strikes")
            .eq("ticker", value: t).gte("expiry", value: "2000-01-01").gte("day", value: since)
            .order("day", ascending: true).order("expiry", ascending: true)
            .execute()
        return try d.decode([WallDay].self, from: res.data)
    }
    static func addDays(_ iso: String, _ n: Int) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        return f.string(from: d.addingTimeInterval(Double(n) * 86_400))
    }
    static func days(_ from: String, _ to: String) -> Int {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        guard let a = f.date(from: from), let b = f.date(from: to) else { return 0 }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }
    /// The third Friday (or the Thursday before a holiday Friday): a standard monthly.
    static func isMonthly(_ e: String) -> Bool {
        let p = e.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let d = Calendar(identifier: .gregorian).date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) else { return false }
        let wd = Calendar(identifier: .gregorian).component(.weekday, from: d)
        return (wd == 6 && (15...21).contains(p[2])) || (wd == 5 && (14...20).contains(p[2]))
    }
}

struct SunnyWalls: View {
    let t: String
    let px: Double
    let today: String
    /// Next Friday's expiry (the sells): the screen opens on it.
    let sells: String?
    /// The tags under each expiry: Your sells, Your hedge · calls held, Your hedge · new buys.
    let tags: [String: [String]]
    /// Inside another screen's scroll (the Gamma tab's watchlist names): no scroll, background or nav bar.
    var embedded = false
    @State private var rows: [WallDay] = []
    @State private var loaded = false
    @State private var exp: String?
    @State private var allOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        if embedded {
            content.task(id: t) { await load() }
        } else {
            screen
        }
    }

    private func load() async {
        rows = (try? await WallsData.load(t, today: today)) ?? []
        loaded = true
        #if DEBUG && targetEnvironment(simulator)
        // `-wallsExp 2027-01-15` opens that expiry, `-wallsAll` opens All strikes (screenshots).
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-wallsExp"), i + 1 < a.count { exp = a[i + 1] }
        if a.contains("-wallsAll") { allOpen = true }
        #endif
    }

    private var screen: some View {
        ZStack {
            SBackground()
            ScrollView {
                content
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Walls")
        .navigationBarTitleDisplayMode(.large)
        .navigationSubtitle("\(t) · $\(PF.price(px)) · \(PWays.weekday(today)) \(PF.monthDay(today))")
        .task(id: t) { await load() }
    }

    private var content: some View {
                VStack(alignment: .leading, spacing: 16) {
                    Text("1st wall has the most gamma · orange: moved to a new strike")
                        .sType(SType(size: 13, weight: 400, line: 18, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted)
                        .padding(.horizontal, 4)
                    if loaded && rows.isEmpty {
                        Text("Walls are not in yet. They are saved after each close.")
                            .sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false)
                            .foregroundStyle(S.muted)
                            .padding(.horizontal, 4)
                    }
                    if let e = cur {
                        chips
                        header(e)
                        tiles(e)
                        week(e)
                        allStrikes(e)
                    }
                }
    }

    // MARK: The expiries

    /// The last close's expiries.
    private var lastDay: String? { rows.map(\.day).max() }
    private var latest: [WallDay] { rows.filter { $0.day == lastDay } }
    /// Weeklies: the next three. Monthlies: the next two, the quarterly months, and any hedge expiry.
    private var groups: [(String, [String])] {
        let exps = latest.map(\.expiry).filter { $0 > today || ($0 == today && lastDay ?? "" < today) }.sorted()
        let wk = Array(exps.filter { !WallsData.isMonthly($0) }.prefix(3))
        let ms = exps.filter(WallsData.isMonthly)
        let mo = ms.enumerated().filter { i, e in
            i < 2 || [1, 3, 6, 9, 12].contains(Int(e.dropFirst(5).prefix(2)) ?? 0) || tags[e] != nil
        }.map(\.element)
        return [("Weeklies", wk), ("Monthlies", mo)].filter { !$0.1.isEmpty }
    }
    private var cur: WallDay? {
        let all = groups.flatMap(\.1)
        let e = exp.flatMap { all.contains($0) ? $0 : nil } ?? sells.flatMap { all.contains($0) ? $0 : nil } ?? all.first
        return latest.first { $0.expiry == e }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups, id: \.0) { g in
                VStack(alignment: .leading, spacing: 6) {
                    Text(g.0).sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted).padding(.leading, 4)
                        .accessibilityAddTraits(.isHeader)
                    PWrap(spacing: 6) {
                        ForEach(g.1, id: \.self) { e in chip(e) }
                    }
                }
            }
        }
    }

    private func chip(_ e: String) -> some View {
        let on = e == cur?.expiry
        return Button {
            guard !on else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduce ? nil : S.standard(0.2)) { exp = e }
        } label: {
            Text(PF.monthDay(e)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false)
                .foregroundStyle(on ? S.paper : S.ink)
                .padding(.horizontal, 14).frame(height: 36)
                .background(Capsule().fill(on ? S.ink : S.tileWalls))
                .overlay(Capsule().strokeBorder(on ? .clear : S.line, lineWidth: 0.5))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(POpacityPress())
        .padding(.vertical, -4)
        .accessibilityLabel(PF.monthDay(e) + ((tags[e] ?? []).isEmpty ? "" : ", " + (tags[e] ?? []).joined(separator: ", ")))
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: The expiry's head: days left, its tags, the flip and the sleeping wall

    private func header(_ e: WallDay) -> some View {
        let n = WallsData.days(today, e.expiry)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(PF.monthDay(e.expiry)).sType(SType(size: 20, weight: 700, line: 24, tracking: 0)).foregroundStyle(S.ink)
                    .contentTransition(.numericText())
                    .accessibilityAddTraits(.isHeader)
                Text(n == 1 ? "1 day" : "\(n) days").sType(SType(size: 15, weight: 500, line: 20, tracking: 0)).foregroundStyle(S.muted)
                Spacer(minLength: 0)
                ForEach(tags[e.expiry] ?? [], id: \.self) { tg in
                    Text(tg).sType(SType(size: 12, weight: 600, line: 12, tracking: 0), tabular: false)
                        .foregroundStyle(S.ink).lineLimit(1)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Capsule().fill(S.track))
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                }
            }
            if let f = e.flip {
                (Text("Flip \(PF.price(f))").font(SType(size: 13, weight: 600, line: 18, tracking: 0).font(tabular: true)).foregroundStyle(S.ink)
                 + Text(px >= f ? " · calmer" : " · choppier").font(SType(size: 13, weight: 500, line: 18, tracking: 0).font()).foregroundStyle(S.muted))
                    .sType(SType(size: 13, weight: 600, line: 18, tracking: 0))
            }
            ForEach(sleeping(e), id: \.0) { s in
                (Text(s.0).font(SType(size: 13, weight: 600, line: 18, tracking: 0).font(tabular: true)).foregroundStyle(S.ink)
                 + Text(s.1).font(SType(size: 13, weight: 500, line: 18, tracking: 0).font()).foregroundStyle(S.muted))
                    .sType(SType(size: 13, weight: 600, line: 18, tracking: 0))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4).padding(.top, 4)
    }

    /// "Most contracts: 47.5 (42,765)", ", wakes if NKE rallies" (puts: drops).
    private func sleeping(_ e: WallDay) -> [(String, String)] {
        var out: [(String, String)] = []
        if let c = e.sleep?.call { out.append(("Most contracts: \(PF.strike(c.k)) (\(PWays.us(c.oi)))", ", wakes if \(t) rallies")) }
        if let p = e.sleep?.put { out.append(("Most put contracts: \(PF.strike(p.k)) (\(PWays.us(p.oi)))", ", wakes if \(t) drops")) }
        if out.count == 1, e.sleep?.put != nil { out[0].0 = out[0].0.replacingOccurrences(of: "Most put contracts", with: "Most contracts") }
        return out
    }

    // MARK: The four walls

    /// The close before this one for the same expiry.
    private func prev(_ e: WallDay) -> WallDay? { rows.filter { $0.expiry == e.expiry && $0.day < e.day }.max { $0.day < $1.day } }

    private func tiles(_ e: WallDay) -> some View {
        let names = ["Calls · 1st wall", "Calls · 2nd wall", "Puts · 1st wall", "Puts · 2nd wall"], p = prev(e)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                let w = e.walls[i], pw = p?.walls[i]
                wallTile(names[i], k: w.k, g: w.g, pk: pw?.k ?? nil, pg: pw?.g ?? nil)
            }
        }
    }

    private func wallTile(_ label: String, k: Double?, g: Double?, pk: Double?, pg: Double?) -> some View {
        let moved = k != nil && pk != nil && abs(k! - pk!) > 1e-6
        let dg = (g != nil && pg != nil && !moved) ? abs(g!) - abs(pg!) : nil
        // "↑ 0.4M · 7%" (a small wall in K); "no change" when it rounds to 0%.
        let ch: String = moved ? "from \(PF.strike(pk!))"
            : dg.map { d in
                let pc = Int((abs(d) / max(1, abs(pg!)) * 100).rounded())
                let a = abs(d) >= 1e5 ? String(format: "%.1fM", abs(d) / 1e6) : "\(Int((abs(d) / 1e3).rounded()))K"
                return pc == 0 ? "no change" : (d > 0 ? "↑ " : "↓ ") + a + " · \(pc)%"
            } ?? ""
        let dp = k.map { PWays.dist($0, px) } ?? 0, up = (k ?? 0) >= px
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.muted)
            Text(k.map(PF.strike) ?? "None").sType(SType(size: 20, weight: 700, line: 24, tracking: 0)).foregroundStyle(S.ink)
                .contentTransition(.numericText())
            Text(k == nil ? " " : (up ? "↑ " : "↓ ") + String(format: "%.1f%%", dp))
                .sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.muted)
            HStack(spacing: 6) {
                Text(g.map(PWays.gamma) ?? "").foregroundStyle(S.ink)
                Text(ch).foregroundStyle(moved ? S.orangeDeep : S.muted)
            }
            .sType(SType(size: 13, weight: 600, line: 18, tracking: 0))
            .lineLimit(1).minimumScaleFactor(0.85)
            .padding(.top, 4)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(S.tileWalls))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(S.line, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(k == nil ? "\(label), none" : "\(label) \(PF.strike(k!)), \(String(format: "%.1f", dp)) percent \(up ? "above" : "below")"
            + (g.map { ", \(String(format: "%.1f", abs($0) / 1e6)) million gamma" } ?? "")
            + (moved ? ", moved today from \(PF.strike(pk!))" : ch == "no change" ? ", no change since yesterday" : ch.isEmpty ? "" : ", \(ch) since yesterday"))
    }

    // MARK: The week at the close

    private func week(_ e: WallDay) -> some View {
        let days = Array(rows.filter { $0.expiry == e.expiry }.sorted { $0.day < $1.day }.suffix(5))
        let cols: [GridItem] = [GridItem(.fixed(44), spacing: 4, alignment: .leading)] + Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .trailing), count: 4)
        return VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: cols, spacing: 0) {
                Text("Day").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(["Call 1st", "Call 2nd", "Put 1st", "Put 2nd"], id: \.self) { Text($0).lineLimit(1) }
            }
            .sType(SType(size: 11, weight: 600, line: 14, tracking: 0), tabular: false)
            .foregroundStyle(S.muted)
            .padding(.top, 10).padding(.bottom, 4)
            ForEach(Array(days.enumerated()), id: \.element.day) { i, r in
                let last = i == days.count - 1, before = i > 0 ? days[i - 1] : nil
                LazyVGrid(columns: cols, spacing: 0) {
                    Text(r.day == today ? "Today" : PWays.weekday(r.day))
                        .sType(SType(size: 12, weight: last ? 700 : 500, line: 16, tracking: 0), tabular: false)
                        .foregroundStyle(r.day == today || last ? S.ink : S.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(0..<4, id: \.self) { j in
                        cell(r.walls[j], before?.walls[j], bold: last)
                    }
                }
                .padding(.vertical, 5)
                .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
            }
            Text("Each day at the close: the wall's strike, its gamma, and the change in gamma from the day before. Orange: the wall moved to that strike that day.")
                .sType(SType(size: 12, weight: 500, line: 16, tracking: 0), tabular: false)
                .foregroundStyle(S.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8).padding(.bottom, 4)
                .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
        }
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(S.tileWalls))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(S.line, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("The week, day by day")
    }

    private func cell(_ w: (k: Double?, g: Double?), _ b: (k: Double?, g: Double?)?, bold: Bool) -> some View {
        let moved = b != nil && w.k != nil && b!.k != nil && abs(w.k! - b!.k!) > 1e-6
        let q: String? = {
            guard let b, let g = w.g, let pg = b.g, abs(pg) > 0 else { return nil }
            let v = Int(((abs(g) - abs(pg)) / abs(pg) * 100).rounded())
            return v == 0 ? "same" : (v > 0 ? "↑ " : "↓ ") + "\(abs(v))%"
        }()
        return VStack(alignment: .trailing, spacing: 0) {
            Text(w.k.map(PF.strike) ?? "None").sType(SType(size: 13, weight: bold ? 700 : 500, line: 16, tracking: 0))
                .foregroundStyle(moved ? S.orangeDeep : S.ink)
            Text(w.g.map(PWays.gamma) ?? " ").sType(SType(size: 11, weight: 500, line: 13, tracking: 0)).foregroundStyle(S.muted)
            if let q {
                Text(q).sType(SType(size: 11, weight: 500, line: 13, tracking: 0)).foregroundStyle(S.muted).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: All strikes, collapsed

    private func allStrikes(_ e: WallDay) -> some View {
        // Strikes with open interest only: a listed strike nobody holds says nothing.
        let ks = (e.strikes ?? []).filter { $0.oi > 0 }.sorted { $0.k > $1.k }
        let callW = Set([e.callWall, e.callWall2].compactMap { $0 }), putW = Set([e.putWall, e.putWall2].compactMap { $0 })
        let sl = Set([e.sleep?.call?.k, e.sleep?.put?.k].compactMap { $0 })
        let cols: [GridItem] = [GridItem(.fixed(52), spacing: 6, alignment: .leading)] + Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .trailing), count: 3)
        let line = ks.firstIndex { $0.k < px } ?? ks.count
        return DisclosureGroup(isExpanded: $allOpen) {
            VStack(alignment: .leading, spacing: 0) {
                LazyVGrid(columns: cols, spacing: 0) {
                    Text("Strike").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Calls"); Text("Puts"); Text("Contracts")
                }
                .sType(SType(size: 11, weight: 600, line: 14, tracking: 0), tabular: false)
                .foregroundStyle(S.muted)
                .padding(.top, 6).padding(.bottom, 4)
                .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
                ForEach(Array(ks.enumerated()), id: \.element.k) { i, r in
                    if i == line { priceLine }
                    let cw = callW.contains(r.k), pw = putW.contains(r.k), s = sl.contains(r.k)
                    let f: (Bool) -> Font = { SType(size: 13, weight: $0 ? 700 : 500, line: 16, tracking: 0).font(tabular: true) }
                    LazyVGrid(columns: cols, spacing: 0) {
                        Text(PF.strike(r.k)).font(f(cw || pw || s)).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(S.ink)
                        Text(PWays.gamma(r.call)).font(f(cw)).foregroundStyle(cw ? S.ink : S.muted)
                        Text(PWays.gamma(r.put)).font(f(pw)).foregroundStyle(pw ? S.ink : S.muted)
                        Text(PWays.us(r.oi)).font(f(s)).foregroundStyle(s ? S.ink : S.muted)
                    }
                    .sType(SType(size: 13, weight: 500, line: 16, tracking: 0))
                    .frame(minHeight: 30)
                    .overlay(alignment: .top) { Rectangle().fill(S.pRule).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
                if line == ks.count { priceLine }
            }
            .padding(.bottom, 8)
        } label: {
            HStack(spacing: 8) {
                Text("All strikes").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Text("\(ks.count) strikes").sType(SType(size: 13, weight: 500, line: 18, tracking: 0)).foregroundStyle(S.muted)
            }
        }
        .disclosureGroupStyle(PShowHide())
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(S.tileWalls))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(S.line, lineWidth: 0.5))
    }

    /// A dashed line at today's price, "$35.28 today".
    private var priceLine: some View {
        HStack(spacing: 8) {
            Line().stroke(S.muted, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(height: 1.5).opacity(0.5)
            Text("$\(PF.price(px)) today").sType(SType(size: 11, weight: 600, line: 14, tracking: 0)).foregroundStyle(S.muted)
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
    private struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

/// All strikes' header: the label, then Show or Hide on the right (block 13d); the system's own
/// open and close underneath.
private struct PShowHide: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduce ? nil : S.standard(0.3)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    configuration.label
                    Spacer(minLength: 0)
                    Text(configuration.isExpanded ? "Hide" : "Show").sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false)
                        .foregroundStyle(S.muted)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(POpacityPress())
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}

/// Chips that wrap onto a second row (the Walls expiries).
struct PWrap: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let W = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, w: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > W { y += row + spacing; x = 0; row = 0 }
            x += s.width + spacing; row = max(row, s.height); w = max(w, x - spacing)
        }
        return CGSize(width: proposal.width ?? w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX && x + s.width > b.maxX { y += row + spacing; x = b.minX; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}
