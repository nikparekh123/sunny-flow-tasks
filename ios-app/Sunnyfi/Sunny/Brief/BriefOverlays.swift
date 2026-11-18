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
        var k: Double = 0; var put = false; var q: Double = 0
        /// Its expiry (ISO) and whether it ends by this Friday (the server's `wk`).
        var ex = ""; var wk = true }

    /// The sold legs: the server's real ones (answer 2), or the sample book's in a -sample run.
    private var rows: [Row] {
        if !BriefDebug.sample {
            // Every sold leg (Nik, 18 Nov 2026, option A: the same legs as Your book), with its expiry and whether it ends
            // by Friday; an older server sends no `wk`: every leg counts as this week's.
            return live["legs"].array.enumerated().map { i, l in
                let t = l["t"].string ?? "", k = l["K"].double ?? 0, q = l["q"].double ?? 0
                return Row(id: "\(t)\(i)", t: t, name: l["name"].string ?? t, leg: "\(String(format: "%g", k)) \(l["put"].bool ? "puts" : "calls") ×\(Int(q))",
                           left: l["tvLeft"].double ?? 0, collected: l["col"].double ?? 0, intrinsic: l["intr"].double ?? 0, perShare: l["tvPer"].double ?? 0,
                           k: k, put: l["put"].bool, q: q, ex: l["ex"].string ?? "", wk: l["wk"].isNull || l["wk"].bool)
            }
        }
        let book = SampleBook.book(acct)
        return SampleBook.names.flatMap { t -> [Row] in
            guard let b = book[t], let q = SampleBook.q[t] else { return [] }
            return b.sold.enumerated().map { i, s in
                let intr = s.put ? max(0, s.k - q.0) : max(0, q.0 - s.k)
                let tv = max(0, s.now - intr)
                return Row(id: "\(t)\(i)", t: t, name: SampleBook.company[t] ?? t, leg: "\(String(format: "%g", s.k)) \(s.put ? "puts" : "calls") ×\(s.q)",
                           left: tv * Double(s.q) * 100, collected: s.at * Double(s.q) * 100, intrinsic: intr, perShare: tv, k: s.k, put: s.put, q: Double(s.q))
            }
        }
    }

    /// A week of decay on every option bought (the server's timeValue.hedges; Nik's groups: every call bought is a
    /// hedge call, LEAPS too). None in a -sample run.
    struct Hedge: Identifiable { let id: String; let t: String; let name: String; let put: Bool; let leg: String; let week: Double }
    private var hedges: [Hedge] {
        live["hedges"].array.enumerated().map { i, h in
            let k = h["K"].double ?? 0, q = h["q"].double ?? 0, put = h["put"].bool
            return Hedge(id: "h\(i)", t: h["t"].string ?? "", name: h["name"].string ?? "", put: put,
                         leg: "\(String(format: "%g", k)) \(put ? "puts" : "calls") · \(h["exLabel"].string ?? "") · \(Int(q)) \(q == 1 ? "contract" : "contracts")",
                         week: h["week"].double ?? 0)
        }
    }
    /// The Friday the week ends, "Fri Nov 20".
    var friday: String? = nil

    // MARK: The receipt (handoff 2026-11-16, App Explorations 159a with 159b's sentence; README 2026-11-18)

    /// One sentence on what needs you (a tap opens the strikes to roll), then the week as a receipt: Coming in (calls
    /// sold, puts sold: time value left, % captured of what was collected), Going out (a week of decay on the hedge calls
    /// and puts), Net by Friday, and In the money on its own line. No bars; a loss is a red number. Every line opens to
    /// its names; privacy masks every dollar figure.
    @State private var openLine: String?
    @State private var needsOpen = false

    private func k(_ v: Double) -> String { BriefWords.plain(SampleEngine.fK(v), privacy: privacy) }
    /// Captured, signed (Nik, 18 Nov 2026: "show negatives"): "52.0% captured", or "2.1% lost" (red) when the legs carry
    /// more time value than they were sold for, as LULU's 110 calls after a 7% day.
    private static func capT(_ left: Double, _ col: Double) -> (t: String, lost: Bool) {
        guard col > 0 else { return ("0% captured", false) }
        let x = (1 - left / col) * 100, a = abs(x)
        let n = a < 0.05 ? "0%" : a < 0.1 ? String(format: "%.2f%%", a) : String(format: "%.1f%%", a)
        return x <= -0.05 ? ("\(n) lost", true) : ("\(n) captured", false)
    }
    /// "Ends Fri Nov 20" from an ISO expiry.
    private static func endsT(_ ex: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: ex) else { return ex }
        f.dateFormat = "EEE MMM d"
        return "Ends " + f.string(from: d)
    }
    private static let callTone = S.dyn(0x327133, 0x65C466), putTone = S.dyn(0x2E5ECA, 0x73B6F9)

    var body: some View {
        let all = rows, rows = all.filter(\.wk), hs = hedges
        let ready = rows.filter { $0.perShare < 0.05 || ($0.collected > 0 && 1 - $0.left / $0.collected >= 0.9) || $0.intrinsic > 0 }
            .sorted { ($0.intrinsic > 0) != ($1.intrinsic > 0) ? $0.intrinsic > 0 : Self.captured($0) > Self.captured($1) }
        let okRows = rows.filter { r in !ready.contains { $0.id == r.id } }
        let tvAll = rows.reduce(0) { $0 + $1.left }, hw = hs.reduce(0) { $0 + $1.week }
        let itm = all.filter { $0.intrinsic > 0 }
        BriefSheetChrome(title: "Time value", sub: friday.map { "By expiry · this week ends \($0)" }, close: close) {
            if all.isEmpty && hs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing sold yet").sType(SType(size: 20, weight: 700, line: 24, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    Text("Time value shows here once calls or puts are sold.").sType(BK.sub, tabular: false).foregroundStyle(S.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    sentence(ready: ready, ok: okRows, all: rows, tvAll: tvAll)
                    VStack(alignment: .leading, spacing: 0) {
                        if !all.isEmpty {
                            head("Coming in · from what you sold")
                            ForEach(Array(Set(all.map(\.ex))).sorted(), id: \.self) { ex in
                                let cs = all.filter { $0.ex == ex && !$0.put }, ps = all.filter { $0.ex == ex && $0.put }
                                Text(Self.endsT(ex)).sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.secondary)
                                    .padding(.top, 8).accessibilityAddTraits(.isHeader)
                                if !cs.isEmpty { soldLine("cs|\(ex)", "Calls sold", Self.callTone, cs) }
                                if !ps.isEmpty { soldLine("ps|\(ex)", "Puts sold", Self.putTone, ps) }
                            }
                        }
                        if !hs.isEmpty {
                            head("Going out · a week of your hedges").padding(.top, 14)
                            let hc = hs.filter { !$0.put }, hp = hs.filter(\.put)
                            if !hc.isEmpty { hedgeLine("hc", "Hedge calls", S.dyn(0x65C466, 0x65C466), hc) }
                            if !hp.isEmpty { hedgeLine("hp", "Hedge puts", S.dyn(0x73B6F9, 0x73B6F9), hp) }
                        }
                        // Net by Friday: time value left less that week of hedges.
                        let net = tvAll - hw
                        HStack(alignment: .firstTextBaseline) {
                            Text("Net by Friday").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).foregroundStyle(S.ink)
                            Spacer()
                            Text(k(net)).sType(SType(size: 20, weight: 800, line: 24, tracking: -0.01)).foregroundStyle(net < -0.5 ? S.red : S.ink)
                        }
                        .padding(.top, 14).padding(.trailing, 22).padding(.top, 10)
                        .overlay(alignment: .top) { Rectangle().fill(S.ink).frame(height: 1.5).padding(.top, 10) }
                        .accessibilityElement(children: .combine)
                        if !itm.isEmpty {
                            itmLine(itm).padding(.top, 14)
                        }
                    }
                }
            }
        }
    }

    private func head(_ t: String) -> some View {
        Text(t).sType(SType(size: 13, weight: 600, line: 18, tracking: 0), tabular: false).foregroundStyle(S.secondary).padding(.bottom, 2)
    }

    /// "3 strikes need you. The other 10 are on track, $X to earn by Friday."; a tap opens the strikes to roll.
    @ViewBuilder private func sentence(ready: [Row], ok: [Row], all: [Row], tvAll: Double) -> some View {
        let n = ready.count, nO = ok.count
        let lead = n > 0 ? "\(n) \(n == 1 ? "strike needs" : "strikes need") you." : "Nothing needs you this week."
        let rest = n > 0 ? (nO > 0 ? " The other \(nO) \(nO == 1 ? "is" : "are") on track, \(k(ok.reduce(0) { $0 + $1.left })) to earn by Friday." : "")
            : (all.count == 1 ? " Your one strike is on track, \(k(tvAll)) to earn by Friday." : " All \(all.count) strikes are on track, \(k(tvAll)) to earn by Friday.")
        VStack(alignment: .leading, spacing: 12) {
            Button {
                guard n > 0 else { return }
                withAnimation(S.moving(.easeOut(duration: 0.25), reduce) ?? .linear(duration: 0)) { needsOpen.toggle() }
            } label: {
                (Text(lead).fontWeight(.semibold) + Text(n > 0 ? Image(systemName: "chevron.right") : Image(systemName: "")).font(.system(size: 13, weight: .heavy)).foregroundStyle(S.secondary)
                 + Text(rest))
                    .sType(SType(size: 19, weight: 400, line: 26, tracking: 0), tabular: true).foregroundStyle(S.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .disabled(n == 0)
            .accessibilityLabel(BSay.words(lead + rest, privacy: privacy))
            .accessibilityHint(n > 0 ? (needsOpen ? "Hides the strikes" : "Shows the strikes to roll") : "")
            if needsOpen && n > 0 {
                VStack(spacing: 0) {
                    ForEach(Array(ready.enumerated()), id: \.offset) { i, r in
                        let x = r.intrinsic > 0
                        HStack(spacing: 12) {
                            BLogo(ticker: r.t, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                (Text(r.name).fontWeight(.semibold).foregroundStyle(S.ink) + Text("  \(r.leg.replacingOccurrences(of: " ×", with: " sold ×"))").foregroundStyle(S.secondary))
                                    .sType(SType(size: 15, weight: 500, line: 19, tracking: 0), tabular: true)
                                Text(x ? "In the money by \(String(format: "%.2f", r.intrinsic))" : "\(Self.captured(r))% captured · \(k(r.left)) left")
                                    .sType(SType(size: 13, weight: 600, line: 17, tracking: 0)).foregroundStyle(x ? S.red : S.act)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Roll").sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(S.act)
                                .padding(.horizontal, 10).frame(height: 24)
                                .background(Capsule().fill(Color(.sRGB, red: 242 / 255, green: 169 / 255, blue: 59 / 255, opacity: 0.18)))
                        }
                        .padding(.vertical, 14)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(S.line).frame(height: 1) } }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(S.chip))
                .transition(.opacity)
            }
        }
    }

    /// A Coming in line: a 4 pt bar in the group's colour, "Calls sold", "52% captured of $4.1K", "$1.9K left", a chevron.
    @ViewBuilder private func soldLine(_ key: String, _ label: String, _ color: Color, _ rs: [Row]) -> some View {
        let left = rs.reduce(0) { $0 + $1.left }, col = rs.reduce(0) { $0 + $1.collected }, on = openLine == key, c = Self.capT(left, col)
        lineButton(key: key, color: color, label: label, sub: "\(c.t) of \(k(col))", subRed: c.lost, value: k(left), valueTone: S.ink, tail: "left",
                   aria: "\(label), \(SampleEngine.fK(left)) left, \(c.t) of \(SampleEngine.fK(col)) sold", on: on)
        if on {
            let byName = Dictionary(grouping: rs, by: \.t).map { ($0.key, $0.value) }.sorted { $0.1.reduce(0) { $0 + $1.left } > $1.1.reduce(0) { $0 + $1.left } }
            VStack(spacing: 0) {
                ForEach(byName, id: \.0) { t, xs in
                    let l = xs.reduce(0) { $0 + $1.left }, c = xs.reduce(0) { $0 + $1.collected }
                    itemRow(t: t, name: xs[0].name, sub: xs.map { String(format: "%g", $0.k) }.joined(separator: " · ") + (xs[0].put ? " puts" : " calls") + " · \(Self.capT(l, c).t)",
                            value: k(l), red: false)
                }
            }
            .padding(.trailing, 22).padding(.bottom, 8)
            .transition(.opacity)
        }
    }

    @ViewBuilder private func hedgeLine(_ key: String, _ label: String, _ color: Color, _ hs: [Hedge]) -> some View {
        let w = hs.reduce(0) { $0 + $1.week }, on = openLine == key
        lineButton(key: key, color: color, label: label, sub: nil, value: k(w), valueTone: S.red, tail: "a week",
                   aria: "\(label), \(SampleEngine.fK(w)) a week", on: on)
        if on {
            VStack(spacing: 0) {
                ForEach(hs) { h in itemRow(t: h.t, name: h.name, sub: h.leg, value: k(h.week), red: true) }
            }
            .padding(.trailing, 22).padding(.bottom, 8)
            .transition(.opacity)
        }
    }

    @ViewBuilder private func itmLine(_ rs: [Row]) -> some View {
        let v = rs.reduce(0) { $0 + $1.intrinsic * $1.q * 100 }, on = openLine == "itm"
        lineButton(key: "itm", color: S.red, label: "In the money", sub: nil, value: k(v), valueTone: S.red, tail: "",
                   aria: "In the money, \(SampleEngine.fK(v))", on: on)
        if on {
            VStack(spacing: 0) {
                ForEach(rs) { r in itemRow(t: r.t, name: r.name, sub: "\(r.leg.replacingOccurrences(of: " ×", with: " sold ×")) · by \(String(format: "%.2f", r.intrinsic))",
                                           value: k(r.intrinsic * r.q * 100), red: true) }
            }
            .padding(.trailing, 22).padding(.bottom, 8)
            .transition(.opacity)
        }
    }

    private func lineButton(key: String, color: Color, label: String, sub: String?, subRed: Bool = false, value: String, valueTone: Color, tail: String, aria: String, on: Bool) -> some View {
        Button {
            withAnimation(S.moving(.easeInOut(duration: 0.25), reduce) ?? .linear(duration: 0)) { openLine = on ? nil : key }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).sType(SType(size: 16, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                    if let sub { Text(sub).sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(subRed ? S.red : S.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                (Text(value).font(.inter(16, 600, tabular: true)).foregroundStyle(valueTone)
                 + Text(tail.isEmpty ? "" : " \(tail)").font(.inter(12, 500)).foregroundStyle(S.secondary))
                    .lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(S.secondary)
                    .rotationEffect(.degrees(on ? 90 : 0))
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(S.line).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSay.words(aria, privacy: privacy))
        .accessibilityHint(on ? "Hides the names" : "Shows the names")
    }

    private func itemRow(t: String, name: String, sub: String, value: String, red: Bool) -> some View {
        HStack(spacing: 10) {
            BLogo(ticker: t, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(S.ink)
                Text(sub).sType(SType(size: 12, weight: 500, line: 16, tracking: 0)).foregroundStyle(S.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(value).sType(SType(size: 14, weight: 600, line: 18, tracking: 0))
                .foregroundStyle(red ? S.dyn(0xFFFFFF, 0x000000) : S.ink)
                .padding(.horizontal, 9).frame(minWidth: 68, minHeight: 30)
                .background(red ? S.red : S.dynA(0x767680, 0.16, 0x767680, 0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    static func captured(_ r: Row) -> Int { r.collected > 0 ? Int(((1 - r.left / r.collected) * 100).rounded()) : 0 }
}

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
