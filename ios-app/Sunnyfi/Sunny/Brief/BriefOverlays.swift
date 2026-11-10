//
//  BriefOverlays.swift
//  Sunny
//
//  The overlays of New Home (block 33): the Time value sheet (from "Time value ›" under the account chart),
//  the economy sheet (from "See the other 7"), and the ticker chart pushed from any name tile. Sheets sit
//  inset 8 with radius 38 and a grabber, close by X, a drag down or a tap on the dim; the push comes from the
//  right and closes with X.
//
//  ⚠ THE TIME VALUE SHEET READS THE BOOK'S OWN SOLD LEGS (answer 2), never the prototype's stand-in book with
//  extra strikes. Ready to roll = under $0.05 a share left, or 90% captured (the notification design's rule).
//

import SwiftUI

// MARK: - Sample price series (the prototype's seeded walk, so lines match it)

enum SampleSeries {
    static func hash(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for u in s.utf16 { h ^= UInt32(u); h = h &* 16777619 }
        return h
    }
    struct RNG {
        var a: UInt32
        mutating func next() -> Double {
            a = a &+ 0x6D2B79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296
        }
    }
    /// 75 closes ending at today's price (the last 22 are the month on screen).
    static func series(_ t: String) -> [Double] {
        guard let q = SampleBook.q[t] else { return [] }
        let sg = (SampleBook.iv[t] ?? 0.3) / (252.0).squareRoot() * 0.8
        var r = RNG(a: hash(t)), s = Array(repeating: 0.0, count: 75)
        s[74] = q.0; s[73] = q.1
        for i in stride(from: 72, through: 0, by: -1) {
            let z = (r.next() + r.next() + r.next() - 1.5) * 2
            s[i] = s[i + 1] / exp(sg * z)
        }
        return s
    }
    /// Weekday sessions ending Tue Oct 27, 2026 (the sample's today), oldest first, market holidays skipped.
    static func dates(_ n: Int) -> [String] {
        let hol: Set<String> = ["2026-09-07", "2026-07-03", "2026-06-19", "2026-05-25", "2026-04-03", "2026-02-16", "2026-01-19",
                                "2026-01-01", "2025-12-25", "2025-11-27"]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard var d = cal.date(from: DateComponents(year: 2026, month: 10, day: 27)) else { return [] }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        var out: [String] = []
        while out.count < n {
            let wd = cal.component(.weekday, from: d), k = f.string(from: d)
            if wd != 1 && wd != 7 && !hol.contains(k) { out.append(k) }
            guard let p = cal.date(byAdding: .day, value: -1, to: d) else { break }
            d = p
        }
        return out.reversed()
    }
    /// About a year of weekday closes, the last 75 the series above.
    static func year(_ t: String) -> [Double] {
        let s0 = series(t), n = 470, m = n - s0.count
        guard !s0.isEmpty else { return [] }
        let sg = (SampleBook.iv[t] ?? 0.3) / (252.0).squareRoot() * 0.8
        var r = RNG(a: hash(t + " year")), c = Array(repeating: 0.0, count: n)
        for (i, x) in s0.enumerated() { c[m + i] = x }
        for i in stride(from: m - 1, through: 0, by: -1) { c[i] = c[i + 1] / exp(sg * (r.next() + r.next() + r.next() - 1.5) * 2) }
        return c
    }
}

// MARK: - Sheet chrome

/// BLogo with the logo at another share of the circle (the ticker pill's is 70%, BLogo's 74%).
struct BriefLogoDisc: View {
    let t: String
    let size: CGFloat
    var pct: CGFloat = 0.74
    var body: some View {
        ZStack {
            Circle().fill(.white)
            if let img = UIImage(named: "logo-\(t)") {
                Image(uiImage: img).resizable().scaledToFit().frame(width: size * pct, height: size * pct)
            } else {
                Text(String(t.prefix(4))).font(.inter(size * 0.26, 700)).foregroundStyle(Color(white: 0.11))
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5).padding(-0.25))
        .accessibilityHidden(true)
    }
}

/// The sheets' head (New Home iPhone Preview, tv and es): the grabber 36 x 5 at 8, 12 under it the title 22/28 bold
/// (and a line 15/20 under it, 4 apart), the close button a 30 pt circle flush with the title's top and 20 from the
/// edge (its 44 pt target reaches 7 past both); then `gap` to the content, which pads `side` and `bottom`.
struct BriefSheetChrome<Content: View>: View {
    let title: String
    var sub: String? = nil
    var gap: CGFloat = 16
    var side: CGFloat = 20
    var bottom: CGFloat = 24
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(S.grabber).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.top, 8)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).sType(SType(size: 22, weight: 700, line: 28, tracking: -0.01), tabular: false).foregroundStyle(S.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let sub { Text(sub).sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.secondary) }
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Path { p in p.move(to: CGPoint(x: 1, y: 1)); p.addLine(to: CGPoint(x: 10, y: 10)); p.move(to: CGPoint(x: 10, y: 1)); p.addLine(to: CGPoint(x: 1, y: 10)) }
                        .stroke(S.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 11, height: 11)
                        .frame(width: 30, height: 30).background(Circle().fill(S.chip))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, -7).padding(.trailing, -7)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, S.margin).padding(.top, 12)
            ScrollView { content().padding(.horizontal, side).padding(.top, gap).padding(.bottom, bottom) }
                .scrollIndicators(.hidden)
        }
        .background(S.sheetFill)
    }
}

// MARK: - Time value

struct TimeValueSheet: View {
    let acct: String
    let privacy: Bool
    /// The server's timeValue (brief.ts): every sold leg still open, with its time value left.
    var live: JSONValue = .null
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// The names folded open to their strikes (SunnyHomeChart tvOpenT): a name with more than one strike opens on a tap.
    @State private var open: Set<String> = []

    struct Row: Identifiable { let id: String; let t: String; let name: String; let leg: String; let left: Double; let collected: Double; let intrinsic: Double; let perShare: Double
        var k: Double = 0; var put = false }

    /// The sold legs: the server's real ones (answer 2), or the sample book's in a -sample run.
    private var rows: [Row] {
        if !BriefDebug.sample {
            return live["legs"].array.enumerated().map { i, l in
                let t = l["t"].string ?? "", k = l["K"].double ?? 0, q = l["q"].double ?? 0
                return Row(id: "\(t)\(i)", t: t, name: l["name"].string ?? t, leg: "\(String(format: "%g", k)) \(l["put"].bool ? "puts" : "calls") ×\(Int(q))",
                           left: l["tvLeft"].double ?? 0, collected: l["col"].double ?? 0, intrinsic: l["intr"].double ?? 0, perShare: l["tvPer"].double ?? 0,
                           k: k, put: l["put"].bool)
            }
        }
        let book = SampleBook.book(acct)
        return SampleBook.names.flatMap { t -> [Row] in
            guard let b = book[t], let q = SampleBook.q[t] else { return [] }
            return b.sold.enumerated().map { i, s in
                let intr = s.put ? max(0, s.k - q.0) : max(0, q.0 - s.k)
                let tv = max(0, s.now - intr)
                return Row(id: "\(t)\(i)", t: t, name: SampleBook.company[t] ?? t, leg: "\(String(format: "%g", s.k)) \(s.put ? "puts" : "calls") ×\(s.q)",
                           left: tv * Double(s.q) * 100, collected: s.at * Double(s.q) * 100, intrinsic: intr, perShare: tv, k: s.k, put: s.put)
            }
        }
    }

    /// The design's bar track: rgba(118,118,128,.2), .32 in dark (the system fill).
    private let barTrack = Color(uiColor: .systemFill)

    private func bar(_ k: Double, height h: CGFloat) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(barTrack)
                Capsule().fill(S.green).frame(width: g.size.width * CGFloat(min(1, max(0, k))))
            }
        }
        .frame(height: h)
    }

    var body: some View {
        let rows = rows
        let left = rows.reduce(0) { $0 + $1.left }, coll = rows.reduce(0) { $0 + $1.collected }
        let cap = coll > 0 ? 1 - left / coll : 0
        // The design's order (SunnyHomeChart RD): in the money first, then the most captured.
        let ready = rows.filter { $0.perShare < 0.05 || ($0.collected > 0 && 1 - $0.left / $0.collected >= 0.9) || $0.intrinsic > 0 }
            .sorted { ($0.intrinsic > 0) != ($1.intrinsic > 0) ? $0.intrinsic > 0 : Self.captured($0) > Self.captured($1) }
        BriefSheetChrome(title: "Time value", close: close) {
            if rows.isEmpty {
                // An account with nothing sold (README 10): one line, no zero bars.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing sold yet").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text("Time value shows here once calls or puts are sold.").sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
            // SunnyHomeChart view="tv": 16 between the total, Ready to roll and the list.
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        BriefWords.line(SampleEngine.fK(left), privacy: privacy)
                            .sType(SType(size: 34, weight: 800, line: 38, tracking: -0.02)).foregroundStyle(S.ink)
                            .fixedSize()   // the number never breaks; the words beside it wrap at large text (Audit 6)
                        Text("left of \(BriefWords.plain(SampleEngine.fK(coll), privacy: privacy)) collected")
                            .accessibilityLabel(BriefMask.spoken("left of \(BriefWords.plain(SampleEngine.fK(coll), privacy: privacy)) collected"))
                            .sType(SType(size: 15, weight: 500, line: 20, tracking: 0)).foregroundStyle(S.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(privacy ? "Time value left, hidden" : BSay.words("\(SampleEngine.fK(left)) left of \(SampleEngine.fK(coll)) collected"))
                    HStack(spacing: 10) {
                        bar(cap, height: 10)
                        // Worth more than it was sold for: a loss so far, in red without a minus sign (colour carries the sign).
                        Text("\(Int(abs(cap * 100).rounded()))% \(cap < -0.005 ? "given back" : "captured")").sType(SType(size: 13, weight: 700, line: 16, tracking: 0))
                            .foregroundStyle(cap < -0.005 ? S.red : S.green).fixedSize()
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Ready to roll").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            Spacer(minLength: 0)
                            if !ready.isEmpty {   // "Nothing ready yet" below says it; no "0 strikes"
                                Text("\(ready.count) strike\(ready.count == 1 ? "" : "s")").sType(SType(size: 13, weight: 600, line: 16, tracking: 0)).foregroundStyle(S.secondary)
                            }
                        }
                        Text("Under $0.05 a share left, or 90% captured").sType(SType(size: 13, weight: 500, line: 17, tracking: 0)).foregroundStyle(S.secondary)
                    }
                    if ready.isEmpty {
                        Text("Nothing ready yet.").sType(BK.body, tabular: false).foregroundStyle(S.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            // 148 wide cards, 10 apart, padding 12 top and bottom and 14 across, radius 16, all as tall as the tallest.
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(ready) { r in rollCard(r) }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, S.margin).padding(.bottom, 2)
                        }
                        .scrollIndicators(.hidden)
                        .padding(.horizontal, -S.margin)
                    }
                }
                let byName = Dictionary(grouping: rows, by: \.t)
                let order = byName.keys.sorted { byName[$0]!.reduce(0) { $0 + $1.left } > byName[$1]!.reduce(0) { $0 + $1.left } }
                // A row per name between 1 pt rules: logo 26, the name 15/18 and its legs 13/16 over a bar 8 and its
                // percent 12/15, left and "of" on the right (64 wide at least), 10 across. The rows render 69 apart
                // in screen 24 (its CSS sums to 65): 13 above and below, 9 down to the bar, 3 down to "of".
                // SunnyHomeChart view="tv": a row per name between 1 pt rules, most left first. A name with more than one
                // strike reads "· 3 strikes" with a chevron and opens on a tap to its strikes (calls by strike up, then
                // puts down), 36 in, 12 apart; "Show every strike" opens them all, "Fold every name" closes them.
                let multi = order.filter { byName[$0]!.count > 1 }
                let allOpen = !multi.isEmpty && multi.allSatisfy { open.contains($0) }
                VStack(alignment: .leading, spacing: 0) {
                    BHairline()
                    ForEach(order, id: \.self) { t in
                        let rs = byName[t]!, isMulti = rs.count > 1, isOpen = isMulti && open.contains(t)
                        VStack(alignment: .leading, spacing: 0) {
                            nameRow(t, rs, isMulti: isMulti, isOpen: isOpen)
                            if isOpen {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(rs.sorted { $0.put != $1.put ? !$0.put : ($0.put ? $0.k > $1.k : $0.k < $1.k) }) { r in strikeRow(r) }
                                }
                                .padding(.leading, 36)
                                .padding(.bottom, 14)
                                .transition(.opacity)   // the design's hcFade .25s
                            }
                        }
                        BHairline()
                    }
                    if !multi.isEmpty {
                        Button {
                            withAnimation(S.moving(S.fade, reduce)) { open = allOpen ? [] : Set(multi) }   // rows push the list: instant under Reduce Motion
                        } label: {
                            Text(allOpen ? "Fold every name" : "Show every strike")
                                .sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                                .frame(height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
            }
            }
        }
    }

    /// A name's row: logo 26, the name 15/18 and "· 3 strikes" (or its one leg) 13/16 with a chevron that turns down
    /// when open, over a bar 8 and its percent 12/15; left and "of" on the right (64 wide at least), 10 across.
    @ViewBuilder private func nameRow(_ t: String, _ rs: [Row], isMulti: Bool, isOpen: Bool) -> some View {
        let l = rs.reduce(0) { $0 + $1.left }, c = rs.reduce(0) { $0 + $1.collected }
        let k = c > 0 ? 1 - l / c : 0
        let sub = isMulti ? "· \(rs.count) strikes" : "· \(rs[0].leg)"
        let row = HStack(spacing: 10) {
            BLogo(ticker: t, size: 26)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 5) {
                    Text(rs.first?.name ?? t).sType(SType(size: 15, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(S.ink)
                        .lineLimit(1).layoutPriority(1)
                    Text(sub).sType(SType(size: 13, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.secondary)
                        .lineLimit(dts > .large ? nil : 1)
                    if isMulti {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(S.secondary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                }
                HStack(spacing: 8) {
                    bar(k, height: 8)
                    Text("\(Int(abs(k * 100).rounded()))%").sType(SType(size: 12, weight: 700, line: 15, tracking: 0))
                        .foregroundStyle(k < -0.005 ? S.red : S.green).frame(minWidth: 34, alignment: .trailing)
                }
            }
            VStack(alignment: .trailing, spacing: 3) {
                BriefWords.line(SampleEngine.fK(l), privacy: privacy).sType(SType(size: 15, weight: 800, line: 18, tracking: 0)).foregroundStyle(S.ink)
                Text("of \(BriefWords.plain(SampleEngine.fK(c), privacy: privacy))")
                    .sType(SType(size: 12, weight: 500, line: 15, tracking: 0)).foregroundStyle(S.secondary)
            }
            .fixedSize()
            .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 13)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        // One stop per name, the sign in words: "Alibaba, 3 strikes, 24% captured, $824 left of $1,090".
        let said = BSay.join([rs.first?.name ?? t, isMulti ? "\(rs.count) strikes" : BSay.words(rs[0].leg),
                              "\(Int(abs(k * 100).rounded()))% \(k < -0.005 ? "given back" : "captured")",
                              privacy ? "amounts hidden" : BSay.words("\(SampleEngine.fK(l)) left of \(SampleEngine.fK(c))")])
        if isMulti {
            Button {
                withAnimation(S.moving(S.fade, reduce)) { if isOpen { open.remove(t) } else { open.insert(t) } }
            } label: { row }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(said)
            .accessibilityValue(isOpen ? "Open" : "Folded")
            .accessibilityAddTraits(.isButton)
        } else {
            row.accessibilityElement(children: .ignore).accessibilityLabel(said)
        }
    }

    /// One strike under an open name: its leg 13/16 over a bar 6 and percent 12/15; left 13/16 bold and "of" 12/15.
    private func strikeRow(_ r: Row) -> some View {
        let k = r.collected > 0 ? 1 - r.left / r.collected : 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(r.leg).sType(SType(size: 13, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.ink).lineLimit(1)
                HStack(spacing: 8) {
                    bar(k, height: 6)
                    Text("\(Int(abs(k * 100).rounded()))%").sType(SType(size: 12, weight: 700, line: 15, tracking: 0))
                        .foregroundStyle(k < -0.005 ? S.red : S.green).frame(minWidth: 34, alignment: .trailing)
                }
            }
            VStack(alignment: .trailing, spacing: 1) {
                BriefWords.line(SampleEngine.fK(r.left), privacy: privacy).sType(SType(size: 13, weight: 700, line: 16, tracking: 0)).foregroundStyle(S.ink)
                Text("of \(BriefWords.plain(SampleEngine.fK(r.collected), privacy: privacy))")
                    .sType(SType(size: 12, weight: 500, line: 15, tracking: 0)).foregroundStyle(S.secondary)
            }
            .fixedSize()
            .frame(minWidth: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSay.join([r.name, BSay.words(r.leg), "\(Int(abs(k * 100).rounded()))% \(k < -0.005 ? "given back" : "captured")",
                                       privacy ? "amounts hidden" : BSay.words("\(SampleEngine.fK(r.left)) left of \(SampleEngine.fK(r.collected))")]))
    }

    /// Share of what was collected that is kept so far, in whole percent (the design's cpN).
    static func captured(_ r: Row) -> Int { r.collected > 0 ? Int(((1 - r.left / r.collected) * 100).rounded()) : 0 }

    /// A Ready to roll card (SunnyHomeChart, Nov 8): logo 32, the name 15/19 and leg 13/17, 8 apart, then at the foot
    /// what is left 24/28 heavy and why, 13/17. In the money it says just "0.41 ITM", 700, red, one line; else
    /// "96% captured" (or "$0.04 a share left") 700, orange (Nik 9 Nov: no "Roll to next week"). Padding 12 top and bottom.
    private func rollCard(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BLogo(ticker: r.t, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).sType(SType(size: 15, weight: 600, line: 19, tracking: 0), tabular: false).foregroundStyle(S.ink).lineLimit(1)
                Text(r.leg).sType(SType(size: 13, weight: 500, line: 17, tracking: 0)).foregroundStyle(S.secondary).lineLimit(1)
                    .accessibilityLabel(BSay.words(r.leg))
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                // At a large text size "left" drops under the amount rather than cutting it (Pass 5).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        BriefWords.line(SampleEngine.fK(r.left), privacy: privacy)
                            .sType(SType(size: 24, weight: 800, line: 28, tracking: -0.01)).foregroundStyle(S.ink)
                        Text("left").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        BriefWords.line(SampleEngine.fK(r.left), privacy: privacy)
                            .sType(SType(size: 24, weight: 800, line: 28, tracking: -0.01)).foregroundStyle(S.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("left").sType(SType(size: 13, weight: 500, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    if r.intrinsic > 0 {
                        Text("\(String(format: "%.2f", r.intrinsic)) ITM").sType(SType(size: 13, weight: 700, line: 17, tracking: 0)).foregroundStyle(S.red)
                            .lineLimit(1)
                            .accessibilityLabel("in the money by \(String(format: "%.2f", r.intrinsic)) dollars")
                    } else {
                        let cp = Self.captured(r)
                        Text(cp >= 90 ? "\(cp)% captured" : "$\(String(format: "%.2f", r.perShare)) a share left")
                            .sType(SType(size: 13, weight: 700, line: 17, tracking: 0)).foregroundStyle(S.act)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(width: 148, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(S.chip))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The economy (12 indicators)

struct EconomySheet: View {
    /// The live sheet (doc.economy); the sample's in sample mode.
    var live: JSONValue = .null
    let close: () -> Void
    var body: some View {
        let e = BriefDebug.sample || live.isNull ? BriefSample.sheets["economy"] : live
        // The design's es sheet: the line under the title in the head, 14 to the cards, 12 apart, 16 from the sides.
        BriefSheetChrome(title: e["title"].string ?? "The economy", sub: e["sub"].string, gap: 14, side: 16, bottom: 32, close: close) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(e["indicators"].array.enumerated()), id: \.offset) { _, c in
                    BIndicatorCard(c: c, width: nil)
                }
            }
        }
    }
}
