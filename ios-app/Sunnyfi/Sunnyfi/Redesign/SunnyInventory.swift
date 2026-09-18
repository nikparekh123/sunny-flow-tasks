//
//  SunnyInventory.swift
//  Sunny · Inventory. `export 20/performance-inventory`, 18 Sep 2026.
//
//  THE TRUE BOOK BEHIND POSITIONS' FOUR TABS. One numbered tile a name (sold)
//  or a position (bought): the ticker first, then the same six readings in the
//  same six places on every tile, then the tags. It retires Roll check's Left
//  to sell, the last place that reading lived.
//
//  ⚠ THE STAR IS A RECOMMENDATION, and there can be several. Nik, 18 Sep 2026:
//  "which one should we pick to sell, that's the whole idea of it".
//    · Sold, SELL THIS NEXT, per side: free contracts, credit at or over the floor,
//      IV not thin.
//    · Calls bought, ADD TO THIS: under water (adding costs less than he paid)
//      and not out of the money.
//    · Puts bought, ADD PUTS HERE: the name's calls are not fully covered, fewer
//      puts held than calls.
//  The tags are still the sheet's placeholders. The floor is his own
//  average credit over strike since 31 Aug, one per side (18 Sep 2026).
//

import SwiftUI

// MARK: - data

struct InventoryCard: Decodable {
    let asOf: String
    /// ⚠ HIS OWN AVERAGE, ONE PER SIDE, credit over strike since 31 Aug. Nik,
    /// 18 Sep 2026: the floor is Credit & theta's figure; puts pay more than
    /// calls on this book, so one floor would pass every put and fail every call.
    let floor: InvFloor
    let sold: InvSides
    let lots: [String: [InvLot]]
    let today: [String: Double]
    let moneyness: [String: String]
    /// Reports before the Friday the next sale would cover, held names only.
    /// Optional so a run against an older deployment decodes.
    let earnings: [String: InvEarn]?
}

struct InvEarn: Decodable { let d: String; let est: Bool }

struct InvSides: Decodable { let calls: [InvSold]; let puts: [InvSold] }
struct InvFloor: Decodable { let calls: Double?; let puts: Double? }

struct InvSold: Decodable, Identifiable {
    let t: String
    let held: Int, sold: Int
    /// The last credit written, as a week's yield on the share, %.
    let cr: Double?
    /// Prices' 1w for the name, %.
    let mv: Double?
    let iv: Double?
    /// Against the name's own history: thin | normal | rich.
    let ivw: String?
    /// The open short legs' delta, contract-weighted.
    let dl: Double?
    /// The last credit in dollars a contract, for "if sold now".
    let lastCr: Int?
    /// ⚠ DELTA IN SHARES, sold against held. Nik, 18 Sep 2026: "344/2000". How
    /// many shares of movement the written legs give away, against how many the
    /// held legs carry. `dUnpriced` counts legs with no delta reading, which are
    /// left out rather than read as zero. Optional for an older deployment.
    let dSold: Int?, dHeld: Int?, dUnpriced: Int?
    /// Net shares for the whole name, Prices' figure: every leg, both sides.
    let net: Int?
    var id: String { t }
    var free: Int { max(0, held - sold) }
    /// Every free contract written at the last credit. An estimate.
    var ifSold: Int { free * (lastCr ?? 0) }
}

/// ⚠ ONE TILE A NAME, CALLS AND PUTS SIDE BY SIDE. Nik, 18 Sep 2026: "can we
/// merge calls sold and put sold and have one card". Week and IV belong to the
/// name, so two tabs printed half of every tile twice.
struct InvSoldName: Identifiable {
    let t: String
    let calls: InvSold?, puts: InvSold?
    var id: String { t }
    var either: InvSold? { calls ?? puts }
    var free: Int { (calls?.free ?? 0) + (puts?.free ?? 0) }
    var ifSold: Int { (calls?.ifSold ?? 0) + (puts?.ifSold ?? 0) }
}

/// One fill still held: [date in, contracts, cost a contract].
struct InvLot: Decodable {
    let d: String, n: Int, cost: Double
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        d = try c.decode(String.self)
        n = try c.decode(Int.self)
        cost = try c.decode(Double.self)
    }
}

// MARK: - the card

struct SunnyInventory: View {
    let block: InventoryCard
    /// Long legs' ledger: the same array Positions and Performance read.
    let legs: [LongLeg]

    enum Tab: Int, CaseIterable {
        case sold, bc, bp
        var label: String {
            switch self {
            case .sold: return "Sold"
            case .bc: return "Calls bought"
            case .bp: return "Puts bought"
            }
        }
        var isSold: Bool { self == .sold }
    }

    /// A new key: the four-tab card stored 0 to 3, and a stale 3 would open on
    /// nothing.
    @AppStorage("sunnyfi.inv.tab3") private var tabRaw = 0
    /// Which bought positions show their lots. Survives the pull and a tab trip.
    @State private var open: Set<String> = []
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tab: Tab { Tab(rawValue: tabRaw) ?? .sold }
    private static let inner: CGFloat = S.content - 48          // 313

    /// Every name with either side, in the book's order.
    private var soldNames: [InvSoldName] {
        let ts = Set(block.sold.calls.map(\.t) + block.sold.puts.map(\.t)).sorted()
        return ts.map { t in
            InvSoldName(t: t, calls: block.sold.calls.first { $0.t == t },
                        puts: block.sold.puts.first { $0.t == t })
        }
    }
    /// A side's floor. With no history yet it is infinite, so nothing is starred
    /// and every credit reads under it rather than over a floor of zero.
    private func floor(_ puts: Bool) -> Double { (puts ? block.floor.puts : block.floor.calls) ?? .infinity }
    /// SELL THIS NEXT, per side: free contracts, credit at or over the side's
    /// floor, IV not thin.
    private func starSide(_ x: InvSold?, puts: Bool) -> Bool {
        guard let x else { return false }
        return x.free > 0 && (x.cr ?? 0) >= floor(puts) && x.ivw != "thin"
    }
    private var boughtRows: [LongLeg] { legs.filter { $0.isCall == (tab == .bc) } }
    private func key(_ l: LongLeg) -> String { "\(l.t) \(l.k)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: 18)
            tabRow
            Spacer().frame(height: 22)
            Text(tab.isSold ? "LEFT TO SELL" : "INVESTED")
                .font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute).sunnyLineBox(S.t10)
            Spacer().frame(height: 12)
            hero
            Spacer().frame(height: 26)
            VStack(spacing: 8) {
                if tab.isSold {
                    let names = soldNames, tags = soldTags(names)
                    ForEach(Array(names.enumerated()), id: \.element.id) { i, r in
                        tile(i) { soldTile(r, no: i + 1, tags: tags[i]) }
                    }
                } else {
                    let rows = boughtRows, tags = boughtTags(rows)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, l in
                        tile(i) { boughtTile(l, no: i + 1, tags: tags[i]) }
                    }
                }
            }
            .id(tabRaw)
            Spacer().frame(height: 24)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 18)
            footer
        }
        .frame(width: Self.inner, alignment: .leading)
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24))
        .frame(width: S.content, alignment: .top)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        .measure("inventory")
        .task(id: tabRaw) {
            /* The fade replays on a tab change, never on the pull. */
            appeared = false
            try? await Task.sleep(for: .milliseconds(20))
            appeared = true
        }
    }

    // MARK: header · tabs · hero

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text("Inventory").font(S.inter(S.t14, S.wBoldN))
                    .tracking(S.track(S.t14, -0.01)).foregroundStyle(S.ink)
                Text(tab.label.lowercased()).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
            }
            Spacer(minLength: 0)
            Text(tab.isSold ? plural(soldNames.count, "name") : plural(boughtRows.count, "position"))
                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .frame(height: 17)
    }

    /* ⚠ POSITIONS' TAB ROW: four words on one rule, spread edge to edge, the
       picked one ink 700 with a 2pt line ON the rule. Never underlined. */
    private var tabRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(Tab.allCases.enumerated()), id: \.element) { i, t in
                if i > 0 { Spacer(minLength: 4) }
                VStack(spacing: 0) {
                    Text(t.label)
                        .font(S.inter(S.t12, t == tab ? S.wBoldN : S.wMidN))
                        .tracking(S.track(S.t12, -0.01))
                        .foregroundStyle(t == tab ? S.ink : S.mute)
                        .lineLimit(1).sunnyLineBox(S.t12)
                    Spacer().frame(height: 10)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(t == tab ? S.ink : .clear).frame(height: 2)
                }
                .fixedSize()
                .contentShape(Rectangle())
                .onTapGesture { tabRaw = t.rawValue }
            }
        }
        .frame(height: 22, alignment: .bottom)
        .background(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: tabRaw)
    }

    private var hero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if tab.isSold {
                let names = soldNames
                big("\(names.reduce(0) { $0 + $1.free })")
                Text("free \u{00B7} \(optMoney(names.reduce(0) { $0 + $1.ifSold })) if sold now")
                    .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
            } else {
                let cost = boughtRows.reduce(0.0) { $0 + $1.cost * Double($1.n) }
                let mark = boughtRows.reduce(0.0) { $0 + $1.m * Double($1.n) }
                big(optMoney(Int(cost.rounded())))
                Text("\(pct1(cost > 0 ? (mark / cost - 1) * 100 : 0)) at mark")
                    .font(S.inter(S.t13, S.wMidSmN))
                    .foregroundStyle(mark < cost ? S.lossText : S.gainText)
            }
        }
        .frame(height: 30)
    }

    private func big(_ s: String) -> some View {
        Text(s).font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.035))
            .foregroundStyle(S.ink).lineLimit(1).fixedSize().sunnyLineBox(S.t30)
    }

    // MARK: the tile

    /// The frame every tile shares, and its fade: .4s, 40 ms a tile.
    @ViewBuilder private func tile<C: View>(_ i: Int, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 15, trailing: 18))
            .frame(width: Self.inner, alignment: .leading)
            .background(S.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(S.ruleColorStrong, lineWidth: 1))
            .opacity(appeared || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : S.easeSettle(0.4).delay(Double(i) * 0.04), value: appeared)
    }

    private func nameRow(no: Int, t: String, k: String?, mny: String?, star: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            (Text("\(no). ").foregroundColor(S.mute) + Text(t).foregroundColor(S.ink))
                .font(S.inter(S.t15, S.wSemiN)).tracking(S.track(S.t15, -0.015))
                .sunnyLineBox(S.t15)
            if let k {
                Text(k).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute).sunnyLineBox(S.t12)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if let mny {
                    HStack(spacing: 5) {
                        Circle().fill(mny == "in" ? S.gainText : mny == "at" ? S.warn : S.hair)
                            .frame(width: 7, height: 7)
                        Text(mny == "in" ? "in the money" : mny == "at" ? "at the money" : "out of the money")
                            .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                            .sunnyLineBox(S.t11)
                    }
                }
                if star {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13)).foregroundStyle(S.warn)
                        .frame(width: 16, height: 16)
                        .accessibilityLabel("good to add")
                }
            }
        }
        .lineLimit(1)
        .frame(height: 15)
    }

    private struct Cell {
        let label: String, value: String, ink: Color
        var tap: (() -> Void)? = nil
    }

    /// Six cells, 3 x 2, 87 wide: label 11/400 over figure 14/600.
    private func cells(_ cs: [Cell]) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 16) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in
                        let c = cs[row * 3 + col]
                        VStack(alignment: .leading, spacing: 7) {
                            Text(c.label).font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                                .lineLimit(1).sunnyLineBox(S.t11)
                            if let tap = c.tap {
                                /* ⚠ THE ONE UNDERLINE ON THE CARD: Held, which opens the lots. */
                                Text(c.value).font(S.inter(S.t14, S.wSemiN))
                                    .tracking(S.track(S.t14, -0.01)).foregroundStyle(c.ink)
                                    .lineLimit(1).sunnyLineBox(S.t14).sunnyHint()
                                    .padding(.vertical, 8).contentShape(Rectangle())
                                    .onTapGesture(perform: tap)
                                    .padding(.vertical, -8)
                            } else {
                                Text(c.value).font(S.inter(S.t14, S.wSemiN))
                                    .tracking(S.track(S.t14, -0.01)).foregroundStyle(c.ink)
                                    .lineLimit(1).sunnyLineBox(S.t14)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(height: 80)
    }

    private func tags(_ ts: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(ts, id: \.self) { t in
                Text(t).font(S.inter(S.t10, S.wMidSmN)).foregroundStyle(S.mute)
                    .sunnyLineBox(S.t10)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(S.wash))
            }
        }
        .padding(.top, 16)
    }

    // MARK: sold

    /* ⚠ A TWO-COLUMN TABLE, NOT SIX CELLS. The rows are the four readings a
       side owns; the columns are calls and puts; the star sits on the side
       worth writing, so a name can say "puts, not calls". Week and IV follow
       under a rule, once, because they are the name's. */
    @ViewBuilder private func soldTile(_ x: InvSoldName, no: Int, tags ts: [String]) -> some View {
        let e = block.earnings?[x.t]
        HStack(alignment: .center, spacing: 8) {
            (Text("\(no). ").foregroundColor(S.mute) + Text(x.t).foregroundColor(S.ink))
                .font(S.inter(S.t15, S.wSemiN)).tracking(S.track(S.t15, -0.015))
                .sunnyLineBox(S.t15)
            Spacer(minLength: 0)
            if let e {
                HStack(spacing: 5) {
                    Circle().fill(S.warn).frame(width: 7, height: 7)
                    Text("earnings \(weekday(e.d))\(e.est ? " (est.)" : "")")
                        .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                        .sunnyLineBox(S.t11)
                }
            }
        }
        .lineLimit(1).frame(height: 15)
        Spacer().frame(height: 16)
        VStack(alignment: .leading, spacing: 12) {
            sideRow("", x.calls, x.puts, head: true) { _, _ in ("", S.ink) }
            sideRow("Free", x.calls, x.puts) { s, _ in
                guard let s else { return ("\u{2013}", S.mute) }
                return ("\(s.free) of \(s.held)", s.free > 0 ? S.ink : S.mute)
            }
            sideRow("Credit", x.calls, x.puts) { s, puts in
                guard let s, let cr = s.cr else { return ("\u{2013}", S.mute) }
                return (String(format: "%.2f%%", cr), cr >= floor(puts) ? S.gainText : S.lossText)
            }
            /* ⚠ WHAT THE NET WOULD BE IF THIS SIDE'S FREE CONTRACTS WERE SOLD.
               Nik, 18 Sep 2026: "just say current delta and if added what it
               would be". Current sits on the shared line; this row is the
               after. A contract not yet written has no delta, so it is taken at
               0.30, the 30-delta weekly Premium now prices with: a sold call
               takes 30 shares off the net, a sold put adds 30. */
            sideRow("Net if sold", x.calls, x.puts) { s, puts in
                guard let s, s.free > 0, let net = x.either?.net else { return ("\u{2013}", S.mute) }
                let after = net + (puts ? 1 : -1) * s.free * Self.newDelta
                /* Now → after, so the change reads in the row. Nik, 18 Sep 2026:
                   the current figure on the shared line was too easy to miss.
                   Signs only when negative, and no unit, to fit the column. */
                let f: (Int) -> String = { ($0 < 0 ? "\u{2212}" : "") + abs($0).formatted() }
                return ("\(f(net)) \u{2192} \(f(after))", S.ink)
            }
            sideRow("If sold now", x.calls, x.puts) { s, _ in
                guard let s, s.free > 0, s.lastCr != nil else { return ("\u{2013}", S.mute) }
                return (optMoney(s.ifSold), S.ink)
            }
        }
        Spacer().frame(height: 14)
        Rectangle().fill(S.ruleColorStrong).frame(height: 1)
        Spacer().frame(height: 12)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            let w = x.either?.mv
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Week").font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                Text(w.map(move) ?? "\u{2013}").font(S.inter(S.t12, S.wSemiN))
                    .foregroundStyle(w == nil || abs(w ?? 0) < 0.05 ? S.mute : ((w ?? 0) < 0 ? S.lossText : S.gainText))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(x.either?.ivw.map { "IV \u{00B7} \($0)" } ?? "IV")
                    .font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                Text(x.either?.iv.map { "\(Int($0.rounded()))%" } ?? "\u{2013}")
                    .font(S.inter(S.t12, S.wSemiN)).foregroundStyle(x.either?.iv == nil ? S.mute : S.ink)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Net").font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                Text(x.either?.net.map(shares) ?? "\u{2013}")
                    .font(S.inter(S.t12, S.wSemiN)).foregroundStyle(S.ink)
            }
        }
        .lineLimit(1).frame(height: 12)
        if !ts.isEmpty { tags(ts) }
    }

    /// One row of the sold table: a label, then the calls and puts figures in
    /// two fixed columns. The head row prints the side names with their stars.
    private func sideRow(_ label: String, _ c: InvSold?, _ p: InvSold?, head: Bool = false,
                         _ fig: @escaping (InvSold?, Bool) -> (String, Color)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(S.inter(S.t11, S.wMidSmN)).foregroundStyle(S.mute)
                .frame(width: 85, alignment: .leading)
            ForEach([false, true], id: \.self) { puts in
                let side = puts ? p : c
                Group {
                    if head {
                        HStack(spacing: 5) {
                            Text(puts ? "Puts" : "Calls").font(S.inter(S.t12, S.wSemiN))
                                .foregroundStyle(side == nil ? S.mute : S.ink2)
                            if starSide(side, puts: puts) {
                                Image(systemName: "star.fill").font(.system(size: 11))
                                    .foregroundStyle(S.warn)
                                    .accessibilityLabel("sell \(puts ? "puts" : "calls") next")
                            }
                        }
                    } else {
                        let f = fig(side, puts)
                        Text(f.0).font(S.inter(S.t14, S.wSemiN))
                            .tracking(S.track(S.t14, -0.01)).foregroundStyle(f.1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .lineLimit(1)
        .frame(height: head ? 12 : 14)
    }

    /// The delta a contract not yet written is taken at, in shares a contract.
    private static let newDelta = 30
    private func shares(_ v: Int) -> String {
        (v < 0 ? "\u{2212}" : "+") + abs(v).formatted() + " sh"
    }

    /// Most free · Best credit · Weakest stock. Best credit is judged against
    /// each side's own floor, so a put is not favoured for paying put rates.
    private func soldTags(_ L: [InvSoldName]) -> [[String]] {
        let mf = L.map(\.free).max() ?? 0
        let over: (InvSoldName) -> Double? = { x in
            [(x.calls?.cr).map { $0 - floor(false) }, (x.puts?.cr).map { $0 - floor(true) }]
                .compactMap { $0 }.max()
        }
        let bc = L.compactMap(over).max()
        let ws = L.compactMap { $0.either?.mv }.min()
        return L.map { x in
            [(x.free == mf && mf > 0) ? "Most free" : nil,
             (bc != nil && over(x) == bc) ? "Best credit" : nil,
             (ws != nil && x.either?.mv == ws) ? "Weakest stock" : nil].compactMap { $0 }
        }
    }

    private func weekday(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return iso }
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: c) else { return iso }
        return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][cal.component(.weekday, from: date) - 1]
    }

    // MARK: bought

    @ViewBuilder private func boughtTile(_ l: LongLeg, no: Int, tags ts: [String]) -> some View {
        let k = key(l)
        let mny = block.moneyness[k] ?? "out"
        let td = block.today[k] ?? 0
        let since = l.cost > 0 ? (l.m / l.cost - 1) * 100 : 0
        let book = legs.reduce(0.0) { $0 + $1.cost * Double($1.n) }
        let pr = protection(l)
        let lots = block.lots[k] ?? []
        nameRow(no: no, t: l.t, k: l.k, mny: mny, star: star(l, mny: mny))
        Spacer().frame(height: 16)
        cells([
            Cell(label: "Held", value: "\(l.n)", ink: S.ink, tap: lots.isEmpty ? nil : {
                if open.contains(k) { open.remove(k) } else { open.insert(k) }
            }),
            Cell(label: "Avg paid", value: optMoney(Int(l.cost.rounded())), ink: S.ink),
            Cell(label: "Today", value: move(td), ink: abs(td) < 0.05 ? S.mute : (td < 0 ? S.lossText : S.gainText)),
            Cell(label: "Since", value: pct1(since), ink: since < 0 ? S.lossText : S.gainText),
            Cell(label: "Of book", value: book > 0 ? "\(Int((l.cost * Double(l.n) / book * 100).rounded()))%" : "\u{2013}", ink: S.ink),
            Cell(label: "Mark", value: optMoney(Int(l.m.rounded())), ink: S.ink),
        ])
        Spacer().frame(height: 14)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(pr.text).font(S.inter(S.t12, S.wSemiN))
                .foregroundStyle(pr.n > 0 ? S.ink : S.lossText)
            if pr.n > 0 {
                Text("\u{00B7} \(pr.share)% protected").font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            }
        }
        .lineLimit(1).frame(height: 12)
        if open.contains(k) && !lots.isEmpty {
            Spacer().frame(height: 14)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 12)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(lots.enumerated()), id: \.offset) { _, lot in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shortDate(lot.d)).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                            .frame(width: 44, alignment: .leading)
                        /* ⚠ EXACT, NOT K. Two NKE lots both read "$1.3k" and moved
                           differently; this is the case Nik's K rule leaves room for,
                           "only use specific numbers when really necessary". */
                        Text("\(lot.n) \u{00D7} $\(Int(lot.cost.rounded()).formatted())")
                            .font(S.inter(S.t12, S.wSemiN)).foregroundStyle(S.ink)
                        Spacer(minLength: 0)
                        let ch = lot.cost > 0 ? (l.m / lot.cost - 1) * 100 : 0
                        Text(pct1(ch)).font(S.inter(S.t12, S.wBoldN))
                            .foregroundStyle(ch < 0 ? S.lossText : S.gainText)
                    }
                    .lineLimit(1).frame(height: 12)
                }
            }
        }
        if !ts.isEmpty { tags(ts) }
    }

    private func star(_ l: LongLeg, mny: String) -> Bool {
        if l.isCall { return l.m < l.cost && mny != "out" }
        let calls = legs.filter { $0.t == l.t && $0.isCall }.reduce(0) { $0 + $1.n }
        let puts = legs.filter { $0.t == l.t && !$0.isCall }.reduce(0) { $0 + $1.n }
        return calls > puts
    }

    /// Biggest · Underwater · Newest.
    private func boughtTags(_ P: [LongLeg]) -> [[String]] {
        let size = P.map { $0.cost * Double($0.n) }
        let newest = P.map { (block.lots[key($0)] ?? []).map(\.d).max() ?? "" }
        let big = size.max() ?? 0, nw = newest.max() ?? ""
        return P.indices.map { i in
            [size[i] == big ? "Biggest" : nil,
             P[i].m < P[i].cost ? "Underwater" : nil,
             (!nw.isEmpty && newest[i] == nw) ? "Newest" : nil].compactMap { $0 }
        }
    }

    /// The same sentence both ways: the puts behind these calls, or the calls
    /// these puts cover. Red only when a call has nothing under it.
    private func protection(_ l: LongLeg) -> (n: Int, share: Int, text: String) {
        let other = legs.filter { $0.t == l.t && $0.isCall != l.isCall }.reduce(0) { $0 + $1.n }
        if l.isCall {
            let share = l.n > 0 ? min(100, Int((Double(other) / Double(l.n) * 100).rounded())) : 0
            /* ⚠ SHORTER THAN THE SHEET'S "held against these", which only fits
               single-digit counts: "10 puts held against these 15 calls ·
               67% protected" ran past the 277pt tile and truncated. */
            return (other, share, other > 0
                ? "\(plural(other, "put")) against \(plural(l.n, "call"))"
                : "no puts against these \(plural(l.n, "call"))")
        }
        let share = min(100, Int((Double(l.n) / Double(max(1, other)) * 100).rounded()))
        return (other, share, other > 0 ? "covers \(plural(other, "\(l.t) call"))" : "no \(l.t) calls to cover")
    }

    // MARK: footer

    private var footer: some View {
        let stats: [(String, String, Color)]
        if tab.isSold {
            let L = soldNames
            stats = [("FREE CALLS", "\(L.reduce(0) { $0 + ($1.calls?.free ?? 0) })", S.ink),
                     ("FREE PUTS", "\(L.reduce(0) { $0 + ($1.puts?.free ?? 0) })", S.ink),
                     ("IF SOLD NOW", optMoney(L.reduce(0) { $0 + $1.ifSold }), S.ink)]
        } else {
            let P = boughtRows
            let cost = P.reduce(0.0) { $0 + $1.cost * Double($1.n) }
            let mark = P.reduce(0.0) { $0 + $1.m * Double($1.n) }
            let lots = P.reduce(0) { $0 + (block.lots[key($1)]?.count ?? 0) }
            stats = [("LOTS", "\(lots)", S.ink),
                     ("AT COST", optMoney(Int(cost.rounded())), S.ink),
                     ("AT MARK", optMoney(Int(mark.rounded())), mark < cost ? S.lossText : S.gainText)]
        }
        return HStack(alignment: .top, spacing: 12) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 5) {
                    Text(s.0).font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                        .foregroundStyle(S.mute).lineLimit(1).sunnyLineBox(S.t10)
                    Text(s.1).font(S.inter(S.t19, S.wBoldN)).tracking(S.track(S.t19, -0.025))
                        .foregroundStyle(s.2).lineLimit(1).sunnyLineBox(S.t19)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 34)
    }

    // MARK: words

    private func plural(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n == 1 ? "" : "s")" }
    /// A move with no sign when it rounds to 0.0 (Prices' rule).
    private func move(_ v: Double) -> String {
        let a = String(format: "%.1f", abs(v))
        return (a == "0.0" ? "" : (v < 0 ? "\u{2212}" : "+")) + a + "%"
    }
    private func pct1(_ v: Double) -> String {
        (v < 0 ? "\u{2212}" : "+") + String(format: "%.1f", abs(v)) + "%"
    }
    private func shortDate(_ iso: String) -> String {
        let p = iso.split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]), (1...12).contains(m) else { return iso }
        return "\(d) \(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][m - 1])"
    }
}
