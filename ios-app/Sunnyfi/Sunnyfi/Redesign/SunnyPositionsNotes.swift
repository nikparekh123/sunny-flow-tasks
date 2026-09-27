//
//  SunnyPositionsNotes.swift
//  Positions as notes (handoff 17, 27 Sep 2026). One box a name, one sentence
//  a line, in a fixed order: the price · the nearer strike · the farther strike
//  (calls sold only) · what the credit has done · the inventory · one thing to
//  watch. It replaces Positions + Prices (Nik, 27 Sep: "Replace the position
//  card to this").
//
//  ⚠ THE EMOJI SAYS WHAT KIND OF LINE; THE HIGHLIGHT SAYS WHAT KIND OF FACT.
//  Lime the day up / credit kept · coral the day down / in the money /
//  underwater · sky a distance · amber on or within 1.5% of the strike, and
//  Watch · violet a cushion. The five highlights are the same by day and night
//  and always carry the mark ink.
//
//  ⚠ ONE TAP FLIPS THE WHOLE CARD % ↔ $. Every highlight is the same switch;
//  there is no per-line state. The list holds the taller of its two heights
//  for the tab and window, so the footer never moves under the thumb.
//
//  ⚠ RULINGS KEPT OVER THE SHEET: Yield is open credit over what that side's
//  long legs cost (Nik, 15 Sep); "time value left" is against what closing the
//  side costs today. The last-4-weeks line on a sold name is the credit booked
//  for that week's Friday on the name (Nik, 27 Sep), the sheet's "captured by
//  week" not being something the book records.
//

import SwiftUI

private enum NT {
    static let lime = S.hex(0x9EE858), coral = S.hex(0xFF8B7B), sky = S.hex(0xBFE3FF)
    static let amber = S.hex(0xFFE08A), violet = S.hex(0xE2D6FF)
    /// Text on every highlight, both themes.
    static let markInk = S.hex(0x14170F)
    static let limeT = S.dyn(0x2F6A00, 0x9EE858), coralT = S.dyn(0x9B2E1E, 0xFF8B7B)
    /// Brand discs; white ticker on each at 7.5/700. A name without one takes ink.
    static let brand: [String: UInt32] = [
        "NFLX": 0xB20710, "BABA": 0xD9550C, "NKE": 0x14170F, "PEP": 0x004B93, "UBER": 0x14170F,
        "LULU": 0xC8102E, "FIS": 0x2B6E3B, "KR": 0x1F4E9E, "LEN": 0x0A5CA8]

    static func p1(_ v: Double) -> String { String(format: "%.1f%%", abs(v)) }
    static func usd2(_ v: Double) -> String { (v < 0 ? "\u{2212}$" : "$") + String(format: "%.2f", abs(v)) }
    /// `$6.6k` · `$288` · `−$41.2k`
    static func k1(_ v: Double) -> String { optMoney(Int(v.rounded())) }
}

// MARK: - a sentence, as tokens

private enum Tok {
    case w(String)                       // a word, 300
    case b(String)                       // a name or figure, 700
    case bi(String)                      // a figure on the Watch line, 600 ink
    case hl(String, Color, tap: Bool, weight: CGFloat = 600)
}

/// "BABA at $109.80," → one token a word, so the line wraps like prose.
private func words(_ s: String) -> [Tok] { s.split(separator: " ").map { .w(String($0)) } }
private func strong(_ s: String) -> [Tok] { s.split(separator: " ").map { .b(String($0)) } }

private struct Line: Identifiable {
    enum Mark { case disc(t: String, up: Bool), emoji(String), week(up: Bool) }
    let id: Int
    let mark: Mark
    let toks: [Tok]
    var muted = false
}

// MARK: - the card

struct SunnyPositionsNotes: View {
    let positions: [OptionsPosition]
    let legs: [LongLeg]
    let prices: PricesBlock?
    let roll: RollCard?
    let intrinsic: IntrinsicBlock?
    let weekly: [OptionsBook.BookWeek]

    @AppStorage("sunnyfi.nt.tab") private var tab = 0
    /// % or $, the whole card at once. Survives the pull and the tab.
    @AppStorage("sunnyfi.nt.usd") private var usd = false
    @State private var four = false
    @State private var hero = 0
    /// The list's tallest height for this tab and window: a flip never shrinks it.
    @State private var pin: CGFloat = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var put: Bool { tab == 1 || tab == 3 }
    private var bought: Bool { tab >= 2 }

    // MARK: price

    private func row(_ t: String) -> PriceRow? { prices?.rows.first { $0.ticker == t } }
    private func spot(_ t: String) -> Double { row(t)?.spot ?? roll?.names[t]?.spot ?? 0 }
    /// Closes k weeks back, read off Prices' cumulative moves.
    private func back(_ t: String, _ k: Int) -> Double? {
        guard let r = row(t), let sp = r.spot, sp > 0 else { return nil }
        let w: PriceWindow = [.today, .w1, .w2, .w3, .w4][k]
        return r.pct.value(w).map { sp / (1 + $0 / 100) }
    }

    // MARK: one box

    private struct Box: Identifiable {
        let t: String
        let lines: [Line]
        let credit: Double, kept: Double, worth: Double, tv: Double, n: Int
        let inMoney: Bool, near: Bool
        var id: String { t }
    }

    /// `Fri 2 Oct` (a short leg) · `Jan '28` (a LEAP) · `19 Mar '27` (a hedge).
    private func expWord(_ iso: String, _ format: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        f.dateFormat = format
        return f.string(from: d)
    }

    private func line1(_ t: String, _ id: Int) -> Line {
        let sp = spot(t)
        let start = four ? back(t, 4) : back(t, 0)
        let mv = start.map { (sp / $0 - 1) * 100 } ?? 0
        let up = mv >= 0
        let fig = (up ? "up " : "down ") + (usd ? NT.usd2(abs(sp - (start ?? sp))) : NT.p1(mv))
            + (four ? " in 4 wks." : ".")
        return Line(id: id, mark: .disc(t: t, up: up),
                    toks: [.b(t), .w("at"), .b(NT.usd2(sp) + ",")] + [.hl(fig, up ? NT.lime : NT.coral, tap: true)])
    }

    /// Four week lines, oldest first: the week's move and what the week did.
    private func weekLines(_ t: String, figs: [Double], tail: String?) -> [Line] {
        let sp = spot(t)
        let c = [sp] + (1...4).map { back(t, $0) ?? sp }
        return (0..<4).map { i in
            let a = c[4 - i], b = c[3 - i]
            let m = a > 0 ? (b / a - 1) * 100 : 0
            let f = figs[i]
            var toks: [Tok] = [.b("Wk \(i + 1)"), .w("\u{00B7}"), .w(m >= 0 ? "up" : "down"), .w(NT.p1(m) + ",")]
            let txt = (f < 0 ? "\u{2212}" : "+") + NT.k1(abs(f)).replacingOccurrences(of: "\u{2212}", with: "")
            toks.append(.hl(txt + (tail == nil ? "." : ""), f < 0 ? NT.coral : NT.lime, tap: false))
            if let tail { toks += words(tail) }
            return Line(id: 10 + i, mark: .week(up: m >= 0), toks: toks)
        }
    }

    private var boxes: [Box] {
        bought ? boughtBoxes : soldBoxes
    }

    private var soldBoxes: [Box] {
        let side = put ? "put" : "call"
        let cur = weekly.firstIndex { $0.current == true } ?? (weekly.count - 1)
        return positions.compactMap { p -> Box? in
            let ls = p.shorts.filter { ($0.type ?? "call") == side }
            guard !ls.isEmpty else { return nil }
            let t = p.t, sp = spot(t)
            let credit = ls.reduce(0.0) { $0 + Double($1.credit) }
            let worth = ls.reduce(0.0) { $0 + Double($1.value) }
            let tv = ls.reduce(0.0) { $0 + Double($1.tv ?? 0) }
            let n = ls.reduce(0) { $0 + $1.n }
            let kept = credit - worth, pct = credit > 0 ? kept / credit * 100 : 0
            let ks = Array(Set(ls.map(\.k))).sorted { put ? $0 > $1 : $0 < $1 }
            let k = ks[0]
            let room = put ? (1 - k / sp) * 100 : (k / sp - 1) * 100
            let past = room < -0.05, at = abs(room) <= 0.05, close = room < 1.5
            var lines = [line1(t, 0)]
            if four {
                /* The credit booked for each week's Friday on the name. */
                let lo = max(0, cur - 3)
                var figs = Array(p.weekly.count > cur ? p.weekly[lo...cur].map(Double.init) : [])
                while figs.count < 4 { figs.insert(0, at: 0) }
                lines += weekLines(t, figs: figs, tail: "booked.")
            } else {
                let dist = usd ? NT.usd2(abs(sp - k)) : NT.p1(room)
                let k1 = at ? "on the strike." : past ? dist + " in the money." : dist + (put ? " below." : " away.")
                lines.append(Line(id: 1, mark: .emoji("\u{1F3AF}"),
                    toks: strong("$" + rsK(k) + " " + side) + [.w("is"),
                          .hl(k1, past ? NT.coral : (at || close) ? NT.amber : NT.sky, tap: true)]))
                if !put, ks.count > 1 {
                    let k2 = ks[1]
                    let c = (usd ? NT.usd2(k2 - sp) : NT.p1((k2 / sp - 1) * 100)) + " cushion."
                    lines.append(Line(id: 2, mark: .emoji("\u{1F6E1}\u{FE0F}"),
                        toks: strong("$" + rsK(k2) + " call") + [.w("has"), .w("a"), .hl(c, NT.violet, tap: false)]))
                }
                let fig = usd ? NT.k1(abs(kept)) : "\(Int(abs(pct).rounded()))%"
                if kept < 0 {
                    lines.append(Line(id: 3, mark: .emoji("\u{1FA79}"),
                        toks: words("Underwater. Buying back costs") + [.hl(fig, NT.coral, tap: true)]
                            + words("more than the credit.")))
                } else {
                    let mood: (String, String) = pct >= 60 ? ("\u{1F60C}", "Quiet one.")
                        : pct >= 30 ? ("\u{1F642}", "Halfway.") : ("\u{2615}", "Early days.")
                    lines.append(Line(id: 3, mark: .emoji(mood.0),
                        toks: words(mood.1) + [.hl(fig, NT.lime, tap: true)] + words("of the credit is yours.")))
                }
                /* What can be written here: one a long leg on the side. */
                let can = legs.filter { $0.t == t && $0.isCall == !put }.reduce(0) { $0 + $1.n }
                let each = usd ? NT.k1(credit) + "." : NT.usd2(credit / Double(max(1, n)) / 100) + " each."
                lines.append(Line(id: 4, mark: .emoji("\u{1F4E6}"),
                    toks: strong("\(n) of \(can > 0 ? can : n)") + [.w("sold"), .w(usd ? "for" : "at"),
                          .hl(each, NT.sky, tap: true)]))
                let exp = ls.map(\.exp).min() ?? ""
                let d = RollMath.daysTo(exp)
                lines.append(Line(id: 5, mark: .emoji("\u{1F440}"),
                    toks: [.hl("Watch", NT.amber, tap: false, weight: 700), .w("expires")]
                        + expWord(exp, "EEE d MMM").split(separator: " ").enumerated().map { i, s in
                            .bi(String(s) + (i == 2 ? "," : "")) }
                        + words(d <= 0 ? "today." : "\(d) day\(d == 1 ? "" : "s")."),
                    muted: true))
            }
            return Box(t: t, lines: lines, credit: credit, kept: kept, worth: worth, tv: tv, n: n,
                       inMoney: past, near: at || close)
        }
        .sorted { $0.t < $1.t }
    }

    private var boughtBoxes: [Box] {
        let by = Dictionary(grouping: legs.filter { $0.isCall == !put }, by: \.t)
        return by.map { t, ls -> Box in
            let sp = spot(t)
            let n = ls.reduce(0) { $0 + $1.n }
            let paid = ls.reduce(0.0) { $0 + $1.cost * Double($1.n) }
            let now = ls.reduce(0.0) { $0 + $1.m * Double($1.n) }
            let made = now - paid, pct = paid > 0 ? made / paid * 100 : 0
            let main = ls.max { $0.n < $1.n }!
            let k = Double(main.k.dropLast()) ?? 0
            let inK = put ? sp < k : sp > k
            let room = put ? (1 - k / sp) * 100 : (k / sp - 1) * 100
            let at = abs(room) <= 0.05
            var lines = [line1(t, 0)]
            if four {
                /* The dollar change on the legs, week by week. */
                let v = { (f: (LongLeg) -> Double) in ls.reduce(0.0) { $0 + f($1) * Double($1.n) } }
                let w4 = v(\.w4), w3 = v { $0.w3 ?? $0.w4 }, w2 = v(\.w2), w1 = v(\.w1)
                lines += weekLines(t, figs: [w3 - w4, w2 - w3, w1 - w2, now - w1], tail: nil)
            } else {
                let dist = usd ? NT.usd2(abs(sp - k)) : NT.p1(room)
                let k1 = at ? "on the strike." : dist + (inK ? " in the money." : " out of the money.")
                lines.append(Line(id: 1, mark: .emoji("\u{1F3AF}"),
                    toks: strong("$" + rsK(k) + (put ? " put" : " call")) + [.w("is"),
                          .hl(k1, inK ? NT.lime : NT.coral, tap: true)]))
                let fig = (made < 0 ? "\u{2212}" : "+")
                    + (usd ? NT.k1(abs(made)) : "\(Int(abs(pct).rounded()))%")
                lines.append(Line(id: 3, mark: .emoji(made >= 0 ? "\u{1F4B0}" : "\u{1FA79}"),
                    toks: words(made >= 0 ? "Working." : "Behind.") + [.hl(fig, made >= 0 ? NT.lime : NT.coral, tap: true)]
                        + words("on " + NT.k1(paid) + " paid.")))
                let each = usd ? NT.k1(paid) + "." : NT.usd2(paid / Double(max(1, n)) / 100) + " each."
                lines.append(Line(id: 4, mark: .emoji("\u{1F4E6}"),
                    toks: strong("\(n) held") + [.w(usd ? "for" : "at"), .hl(each, NT.sky, tap: true)]))
                let row = intrinsic?.rows.first { $0.t == t }
                let exp = (put ? row?.put?.exp : row?.call?.exp) ?? ""
                let word = exp.isEmpty ? "" : expWord(exp, put ? "d MMM ''yy" : "MMM ''yy")
                lines.append(Line(id: 5, mark: .emoji("\u{1F440}"),
                    toks: [.hl("Watch", NT.amber, tap: false, weight: 700), .w("expires")]
                        + word.split(separator: " ").enumerated().map { i, s in
                            .bi(String(s) + (i == word.split(separator: " ").count - 1 ? (put ? "," : ".") : "")) }
                        + words(put ? "the hedge." : "Hold."),
                    muted: true))
            }
            return Box(t: t, lines: lines, credit: paid, kept: made, worth: now, tv: 0, n: n,
                       inMoney: inK, near: false)
        }
        .sorted { $0.credit > $1.credit }
    }

    // MARK: hero and footer

    private func heroRead(_ bs: [Box]) -> (label: String, fig: String, tail: String) {
        let credit = bs.reduce(0) { $0 + $1.credit }, kept = bs.reduce(0) { $0 + $1.kept }
        let worth = bs.reduce(0) { $0 + $1.worth }, tv = bs.reduce(0) { $0 + $1.tv }
        let pct = credit > 0 ? Int((kept / credit * 100).rounded()) : 0
        let sgn = kept < 0 ? "\u{2212}" : "+"
        if bought {
            return [("SINCE BOUGHT", sgn + "\(abs(pct))%", "\(bs.filter(\.inMoney).count) in the money"),
                    ("DIFFERENCE", sgn + NT.k1(abs(kept)), "on " + NT.k1(credit)),
                    ("WORTH NOW", NT.k1(worth), "if closed")][hero]
        }
        return [("CAPTURED OF CREDIT", "\(pct)%", "unrealized"),
                ("CAPTURED", NT.k1(kept), "of " + NT.k1(credit) + " unrealized"),
                ("TIME VALUE LEFT", NT.k1(tv), "of " + NT.k1(worth) + " to close")][hero]
    }

    private func stats(_ bs: [Box]) -> [(String, String, Color)] {
        let credit = bs.reduce(0) { $0 + $1.credit }, kept = bs.reduce(0) { $0 + $1.kept }
        let worth = bs.reduce(0) { $0 + $1.worth }
        let ink = kept < 0 ? NT.coralT : NT.limeT
        if bought {
            return [("PAID", NT.k1(credit), S.ink), ("WORTH NOW", NT.k1(worth), S.ink),
                    ("DIFFERENCE", (kept < 0 ? "\u{2212}" : "+") + NT.k1(abs(kept)), ink)]
        }
        let inv = legs.filter { $0.isCall == !put }.reduce(0.0) { $0 + $1.cost * Double($1.n) }
        return [("OPEN CREDIT", NT.k1(credit), S.ink), ("WORTH NOW", NT.k1(worth), S.ink),
                ("YIELD", String(format: "%.1f%%", inv > 0 ? credit / inv * 100 : 0), ink)]
    }

    // MARK: body

    var body: some View {
        let bs = boxes
        let h = heroRead(bs)
        let kept = bs.reduce(0) { $0 + $1.kept }
        let side = ["calls sold", "puts sold", "calls bought", "puts bought"][tab]
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Positions").font(S.inter(S.t14, S.wBoldN)).tracking(S.track(S.t14, -0.01))
                        .foregroundStyle(S.ink)
                    Text(side).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.ink2)
                }
                Spacer(minLength: 0)
                Text(bs.isEmpty ? "none open" : "\(bs.reduce(0) { $0 + $1.n }) contracts \u{00B7} \(bs.count) name\(bs.count == 1 ? "" : "s")")
                    .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            }
            .lineLimit(1)
            Spacer().frame(height: 18)
            tabRow
            Spacer().frame(height: 16)
            HStack(spacing: 4) {
                ForEach([(false, "today"), (true, "last 4 weeks")], id: \.1) { v, label in
                    Text(label).font(S.inter(S.t12, four == v ? S.wBoldN : S.wMidN))
                        .foregroundStyle(four == v ? S.paper : S.mute).sunnyLineBox(S.t12)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(four == v ? S.ink : S.wash,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { if four != v { pin = 0; four = v } }
                }
            }
            Spacer().frame(height: 22)
            VStack(alignment: .leading, spacing: 12) {
                Text(h.label).font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                    .foregroundStyle(S.mute).sunnyLineBox(S.t10)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(h.fig).font(S.inter(S.t30, S.wBoldN)).tracking(S.track(S.t30, -0.035))
                        .foregroundStyle(kept < 0 ? NT.coralT : NT.limeT).sunnyLineBox(S.t30)
                        .sunnyHint()
                    Text(h.tail).font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.ink2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { hero = (hero + 1) % 3 }
            Spacer().frame(height: 24)
            VStack(spacing: 10) {
                if bs.isEmpty {
                    HStack(alignment: .top, spacing: 14) {
                        Text("\u{1F634}").font(.system(size: 20)).frame(width: 26, height: 25)
                        Text("No \(side) right now.").font(S.inter(16, S.wLightN)).foregroundStyle(S.mute)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
                    .background(S.wash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                ForEach(Array(bs.enumerated()), id: \.element.id) { i, b in
                    box(b)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .animation(reduceMotion ? nil : S.easeSettle(0.4).delay(Double(i) * 0.04), value: appeared)
                }
            }
            .padding(.horizontal, -14)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hgt in
                if hgt > pin { pin = hgt }
            }
            .frame(minHeight: pin, alignment: .top)
            Spacer().frame(height: 26)
            Rectangle().fill(S.ruleColorStrong).frame(height: 1)
            Spacer().frame(height: 18)
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(stats(bs).enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(s.0).font(S.inter(S.t10, S.wBoldN)).tracking(S.track(S.t10, S.lsLabel))
                            .foregroundStyle(S.mute).lineLimit(1).sunnyLineBox(S.t10)
                        Text(s.1).font(S.inter(S.t19, S.wBoldN)).tracking(S.track(S.t19, -0.025))
                            .foregroundStyle(s.2).lineLimit(1).minimumScaleFactor(0.7).sunnyLineBox(S.t19)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: S.content - 48, alignment: .leading)
        .padding(EdgeInsets(top: 24, leading: 24, bottom: 28, trailing: 24))
        .frame(width: S.content, alignment: .top)
        .background(S.paper)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCardL)
        .monospacedDigit()
        .measure("positions-notes")
        .task(id: "\(tab)|\(four)") {
            appeared = false
            try? await Task.sleep(for: .milliseconds(20))
            appeared = true
        }
    }

    private var tabRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(["Calls sold", "Puts sold", "Calls bought", "Puts bought"].enumerated()), id: \.offset) { i, t in
                if i > 0 { Spacer(minLength: 4) }
                VStack(spacing: 0) {
                    Text(t).font(S.inter(S.t12, i == tab ? S.wBoldN : S.wMidN))
                        .foregroundStyle(i == tab ? S.ink : S.mute).lineLimit(1).sunnyLineBox(S.t12)
                    Spacer().frame(height: 10)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(i == tab ? S.ink : .clear).frame(height: 2)
                }
                .contentShape(Rectangle())
                .onTapGesture { if tab != i { pin = 0; hero = 0; tab = i } }
            }
        }
        .background(alignment: .bottom) { Rectangle().fill(S.ruleColor).frame(height: 1) }
    }

    // MARK: the box

    private func box(_ b: Box) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(b.lines) { l in
                HStack(alignment: .top, spacing: 14) {
                    mark(l.mark).frame(width: 26)
                    SunnyWrap(spacing: 4.3, lineSpacing: 0) {
                        ForEach(Array(l.toks.enumerated()), id: \.offset) { _, t in tok(t, muted: l.muted) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(S.wash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private func tok(_ t: Tok, muted: Bool) -> some View {
        let tr = S.track(16, -0.005)
        switch t {
        case .w(let s):
            Text(s).font(S.inter(16, S.wLightN)).tracking(tr).foregroundStyle(muted ? S.mute : S.ink)
                .fixedSize().frame(height: 24)
        case .b(let s):
            Text(s).font(S.inter(16, S.wBoldN)).tracking(tr).foregroundStyle(S.ink)
                .fixedSize().frame(height: 24)
        case .bi(let s):
            Text(s).font(S.inter(16, S.wSemiN)).tracking(tr).foregroundStyle(S.ink)
                .fixedSize().frame(height: 24)
        case .hl(let s, let c, let tap, let wt):
            let chip = Text(s).font(S.inter(16, wt)).tracking(tr).foregroundStyle(NT.markInk)
                .fixedSize()
                .padding(.horizontal, 5).frame(height: 21.5)
                .background(c, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .frame(height: 24)
            if tap {
                chip.overlay(alignment: .bottom) {
                    SunnyDotsInk().frame(height: 1).padding(.horizontal, 5).offset(y: -3)
                }
                .contentShape(Rectangle())
                .onTapGesture { usd.toggle() }
            } else {
                chip
            }
        }
    }

    @ViewBuilder private func mark(_ m: Line.Mark) -> some View {
        switch m {
        case .emoji(let e):
            Text(e).font(.system(size: 20)).frame(width: 26, height: 25)
        case .week(let up):
            Image(systemName: up ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(NT.markInk)
                .frame(width: 26, height: 26)
                .background(up ? NT.lime : NT.coral, in: Circle())
        case .disc(let t, let up):
            ZStack(alignment: .topLeading) {
                Circle().fill(NT.brand[t].map { S.hex($0) } ?? S.ink)
                    .frame(width: 26, height: 26)
                    .overlay {
                        /* ⚠ THE TICKER FITS ITS DISC. At a flat 7.5 a four-letter
                           ticker ran under the badge ("BAB", "NFL"); it scales to
                           the disc's clear width instead (Nik, 27 Sep). */
                        Text(t).font(S.inter(7.5, S.wBoldN)).tracking(S.track(7.5, 0.02))
                            .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                            .frame(width: 19)
                            .offset(x: -1.5, y: -2)
                    }
                Text(up ? "\u{2191}" : "\u{2193}")
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(NT.markInk)
                    .frame(width: 15, height: 15)
                    .background(up ? NT.lime : NT.coral, in: Circle())
                    .background(Circle().fill(S.wash).frame(width: 19, height: 19))
                    .offset(x: 16, y: 15)
            }
            .frame(width: 26, height: 26, alignment: .topLeading)
        }
    }
}

/// The highlight's dotted underline: the mark ink at .45, on any highlight.
private struct SunnyDotsInk: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                var x: CGFloat = 0
                while x < g.size.width { p.addRect(CGRect(x: x, y: 0, width: 1, height: 1)); x += 3 }
            }
            .fill(Color(red: 20 / 255, green: 23 / 255, blue: 15 / 255).opacity(0.45))
        }
    }
}
