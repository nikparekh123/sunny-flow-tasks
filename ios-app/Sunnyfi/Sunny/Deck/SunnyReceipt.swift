//
//  SunnyReceipt.swift
//  Sunny
//
//  SunnyReport (blocks 06 and 07): the printed receipt that opens full
//  screen over Home from the green report card or the ink theta check card.
//  The desk, a slot, and paper that prints down out of it (2.6 s, 32 steps),
//  then rows that fold open: + and −. UI Kit §27 and §27b.
//
//  Copy is upper case and plain, as the design prints it. No minus signs:
//  a loss, a debit, a fee is red.
//

import SwiftUI

// MARK: - The desk

struct SunnyReceipt<Paper: View>: View {
    let range: String
    let onClose: () -> Void
    @ViewBuilder var paper: Paper

    @State private var printed: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack(alignment: .top) {
            S.desk.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(range).sMono(12, 700, line: 14, tracking: 0.12).foregroundStyle(S.deskInk)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(S.deskInk)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(SPressStyle())
                    .accessibilityLabel("Close report")
                }
                .padding(.leading, 20).padding(.trailing, 12).padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 0) {
                        // The slot the paper comes out of.
                        RoundedRectangle(cornerRadius: 4).fill(S.receiptSlot)
                            .frame(height: 8)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x2A2A2C)).offset(y: 2))
                            .padding(.horizontal, -6)
                            .zIndex(1)
                        VStack(spacing: 0) {
                            paper
                                .padding(.top, 32).padding(.horizontal, 24).padding(.bottom, 8)
                                .frame(maxWidth: .infinity)
                                .background(Color.white)
                            ReceiptEdge().fill(Color.white).frame(height: 12)
                        }
                        .environment(\.colorScheme, .light)
                        .mask(alignment: .top) {
                            GeometryReader { g in Rectangle().frame(height: g.size.height * printed) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task { await print() }
    }

    /// The paper prints down in 32 steps over 2.6 s; Reduce Motion shows it.
    private func print() async {
        guard printed == 0 else { return }
        if reduce { printed = 1; return }
        for k in 1...32 {
            try? await Task.sleep(for: .milliseconds(81))
            printed = CGFloat(k) / 32
        }
    }
}

/// The torn edge: a white strip with 6 pt half-circle bites every 12 pt.
struct ReceiptEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        var x = rect.width
        // Back along the bottom, scalloped.
        p.addLine(to: CGPoint(x: x, y: rect.height - 6))
        let n = Int(ceil(rect.width / 12))
        for k in stride(from: n - 1, through: 0, by: -1) {
            let cx = CGFloat(k) * 12 + 6
            p.addLine(to: CGPoint(x: min(x, cx + 6), y: rect.height))
            p.addArc(center: CGPoint(x: cx, y: rect.height), radius: 6,
                     startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            x = cx - 6
        }
        p.addLine(to: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}

// MARK: - Paper parts

/// "SUNNY" over the report's kind.
struct ReceiptMasthead: View {
    let kind: String
    var body: some View {
        VStack(spacing: 4) {
            Text("SUNNY").sMono(24, 700, line: 28, tracking: 0.3).padding(.leading, 24 * 0.3)
            Text(kind).sMono(12, 600, line: 16, tracking: 0.1)
        }
        .foregroundStyle(S.receiptInk)
        .frame(maxWidth: .infinity)
    }
}

/// A row that folds open: label, value, + or −. Dashed rule under it.
struct ReceiptFold<Content: View>: View {
    let label: String
    let value: String
    var valueColor: Color = S.receiptInk
    var last = false
    @Binding var open: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(S.standard(0.45)) { open.toggle() } } label: {
                HStack(spacing: 12) {
                    Text(label).sMono(13, 700, line: 16, tracking: 0.1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(value).sMono(15, 400, line: 20).foregroundStyle(valueColor)
                    Text(open ? "−" : "+").sMono(18, 600, line: 18).frame(width: 20)
                }
                .foregroundStyle(S.receiptInk)
                .frame(minHeight: 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label.capitalized), \(value)")
            .accessibilityHint(open ? "Folds the detail" : "Shows the detail")
            if open {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
        .overlay(alignment: .bottom) {
            if !last { DashedRule().stroke(S.receiptRule, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1) }
        }
    }
}

struct DashedRule: Shape {
    func path(in r: CGRect) -> Path { Path { $0.move(to: CGPoint(x: 0, y: r.midY)); $0.addLine(to: CGPoint(x: r.width, y: r.midY)) } }
}

/// NKE 36C  EXP ·········· 1,480.00
struct ReceiptLeader: View {
    let name: String
    var how: String? = nil
    var old: String? = nil
    let value: String
    var valueColor: Color = S.receiptInk
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).sMono(12).lineLimit(1).fixedSize()
            if let how { Text(how).sMono(11).foregroundStyle(S.receiptMuted).fixedSize() }
            DashedRule().stroke(S.receiptRule, style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
                .frame(height: 1)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
            if let old {
                Text(old).sMono(12).foregroundStyle(S.receiptMuted).fixedSize()
                Text("→").sMono(12).foregroundStyle(S.receiptMuted)
            }
            Text(value).sMono(12).foregroundStyle(valueColor).fixedSize()
        }
        .foregroundStyle(S.receiptInk)
        .frame(minHeight: 28)
    }
}

struct ReceiptNote: View {
    let text: String
    var body: some View {
        Text(text).sMono(12, line: 18).foregroundStyle(S.receiptMuted)
            .padding(.bottom, 18)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The barcode and the line under it.
struct ReceiptFoot: View {
    let line: String
    var body: some View {
        VStack(spacing: 10) {
            Canvas { ctx, size in
                var x: CGFloat = 0
                while x < size.width {
                    for (a, b) in [(0.0, 2.0), (4, 5), (8, 11), (12, 13)] {
                        ctx.fill(Path(CGRect(x: x + a, y: 0, width: b - a, height: size.height)), with: .color(S.receiptInk))
                    }
                    x += 17
                }
            }
            .frame(height: 36)
            .accessibilityHidden(true)
            Text(line).sMono(11, line: 14, tracking: 0.1).foregroundStyle(S.receiptInk)
        }
        .padding(.top, 24).padding(.bottom, 10)
    }
}

enum R {
    /// 4,592.00 · no sign.
    static func f2(_ v: Double) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal; n.minimumFractionDigits = 2; n.maximumFractionDigits = 2
        return n.string(from: NSNumber(value: abs(v))) ?? "0.00"
    }
    static let mon = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    /// "OCT 13"
    static func day(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return iso }
        return "\(mon[p[1] - 1]) \(p[2])"
    }
    /// "MON OCT 19"
    static func weekdayDay(_ iso: String) -> String {
        "\(DeckBuilder.weekdays[DeckBuilder.weekday(iso)].uppercased()) \(day(iso))"
    }
    /// "NKE 2028-01 70C" → (NKE, JAN 2028, 70, call)
    static func leg(_ s: String) -> (ticker: String, month: String, strike: String, call: Bool)? {
        let p = s.split(separator: " ").map(String.init)
        guard p.count == 3, p[1].count == 7 else { return nil }
        let y = String(p[1].prefix(4)), m = Int(p[1].suffix(2)) ?? 1
        let call = p[2].hasSuffix("C")
        return (p[0], "\(mon[m - 1]) \(y)", String(p[2].dropLast()), call)
    }
    /// "JAN ’28 $70C"
    static func short(_ expiry: String, _ strike: Double, call: Bool = true) -> String {
        let m = Int(expiry.dropFirst(5).prefix(2)) ?? 1
        return "\(mon[m - 1]) ’\(expiry.dropFirst(2).prefix(2)) $\(F.trim(strike))\(call ? "C" : "P")"
    }
}

// MARK: - Report (block 06)

struct ReportPaper: View {
    let report: Deck.Report
    let today: String
    @State private var open: Set<String> = DebugPreset.string("rcpt.open") == "all"
        ? ["realized", "commission", "interest", "unrealized", "best", "up"] : []
    @State private var clipped: Set<Int> = []

    private var monthly: Bool { report.kind == "monthly" }
    private func binding(_ k: String) -> Binding<Bool> {
        Binding(get: { open.contains(k) }, set: { if $0 { open.insert(k) } else { open.remove(k) } })
    }

    var body: some View {
        let kept = report.kept ?? 0
        VStack(alignment: .leading, spacing: 0) {
            ReceiptMasthead(kind: monthly ? "MONTHLY REPORT" : "WEEKLY REPORT")
            VStack(spacing: 6) {
                Text("YOU KEPT").sMono(12, 700, line: 14, tracking: 0.16)
                SNumber(value: kept, format: { "$" + R.f2($0) })
                    .sMono(44, 700, line: 48, tracking: -0.03)
                    .foregroundStyle(kept < 0 ? S.receiptRed : S.receiptInk)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("AFTER COMMISSION + INTEREST").sMono(11, line: 14, tracking: 0.04).foregroundStyle(S.receiptMuted)
            }
            .foregroundStyle(S.receiptInk)
            .frame(maxWidth: .infinity)
            .padding(.top, 36).padding(.bottom, 28)
            DoubleRule()

            let realized = report.realized ?? 0
            ReceiptFold(label: "REALIZED", value: R.f2(realized), valueColor: realized < 0 ? S.receiptRed : S.receiptInk,
                        open: binding("realized")) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array((report.lines ?? []).enumerated()), id: \.offset) { _, l in
                        ReceiptLeader(name: l.leg, how: how(l.how), value: R.f2(l.amount),
                                      valueColor: l.amount < 0 ? S.receiptRed : S.receiptInk)
                    }
                }
                .padding(.trailing, 32).padding(.bottom, 16)
            }
            ReceiptFold(label: "COMMISSION", value: R.f2(report.commission ?? 0),
                        valueColor: (report.commission ?? 0) != 0 ? S.receiptRed : S.receiptInk, open: binding("commission")) {
                ReceiptNote(text: "\(report.trades ?? 0) TRADES · \(R.f2(report.commissionEach ?? 0)) EACH")
            }
            ReceiptFold(label: "INTEREST", value: R.f2(report.interest ?? 0),
                        valueColor: (report.interest ?? 0) < 0 ? S.receiptRed : S.receiptInk, open: binding("interest")) {
                ReceiptNote(text: "MARGIN ON \(F.moneyK(report.borrowed ?? 0).dropFirst()) BORROWED")
            }
            let unr = report.unrealizedNow ?? 0
            ReceiptFold(label: "UNREALIZED", value: R.f2(unr), valueColor: unr < 0 ? S.receiptRed : S.receiptInk,
                        open: binding("unrealized")) {
                ReceiptNote(text: "OPEN LEGS MARKED TO TODAY. NOT LOCKED IN.")
            }
            if let b = report.best {
                ReceiptFold(label: bestTag, value: b.leg, open: binding("best")) {
                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(R.f2(b.amount)).sMono(30, 700, line: 34)
                                .foregroundStyle(b.amount < 0 ? S.receiptRed : S.receiptInk)
                            Text(bestNote(b)).sMono(12, line: 16).foregroundStyle(S.receiptNote)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        BestStamp(sub: stamp, shown: open.contains("best")).padding(.trailing, 4).padding(.top, 4)
                    }
                    .padding(.top, 4).padding(.bottom, 22)
                }
            }
            let coupons = self.coupons
            ReceiptFold(label: "COMING UP", value: "\(coupons.count) \(coupons.count == 1 ? "THING" : "THINGS")",
                        last: true, open: binding("up")) {
                VStack(spacing: 10) {
                    ForEach(Array(coupons.enumerated()), id: \.offset) { i, c in
                        Coupon(c: c, clipped: clipped.contains(i)) {
                            if clipped.contains(i) { clipped.remove(i) } else { clipped.insert(i) }
                        }
                    }
                }
                .padding(.bottom, 18)
            }
            ReceiptFoot(line: "NEXT REPORT · \(R.weekdayDay(nextReport))")
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(S.receiptInk)
    }

    private var bestTag: String {
        guard monthly, let p = report.period else { return "BEST OF THE WEEK" }
        let m = Int(p.from.dropFirst(5).prefix(2)) ?? 1
        return "BEST OF \(DeckBuilder.months[m - 1].uppercased())"
    }
    private var stamp: String {
        guard monthly, let p = report.period else { return "WK \(report.mark)" }
        return R.mon[(Int(p.from.dropFirst(5).prefix(2)) ?? 1) - 1]
    }
    private func how(_ h: String) -> String {
        switch h { case "expired": "EXP"; case "closed": "CLOSED"; default: h.uppercased() }
    }
    private func bestNote(_ b: Deck.Report.Best) -> String {
        var parts: [String] = []
        if let k = b.keptPct { parts.append("KEPT \(Int(k))% OF PREMIUM") }
        if b.how == "expired", let e = b.exp { parts.append("EXP \(DeckBuilder.weekdays[DeckBuilder.weekday(e)].uppercased())") }
        else { parts.append(how(b.how)) }
        return parts.joined(separator: " · ")
    }
    /// The next Monday, or the 1st after a monthly.
    private var nextReport: String {
        if monthly {
            let y = Int(today.prefix(4)) ?? 2026, m = Int(today.dropFirst(5).prefix(2)) ?? 1
            return String(format: "%04d-%02d-01", m == 12 ? y + 1 : y, m == 12 ? 1 : m + 1)
        }
        var x = MarketClock.addDays(today, 1)
        while x.weekday != 2 { x = MarketClock.addDays(x.iso, 1) }
        return x.iso
    }

    struct CouponData { let d: String; let chip: String; let title: String; let why: String }

    private var coupons: [CouponData] {
        guard let u = report.comingUp else { return [] }
        var dated: [(String, CouponData)] = []
        for e in u.earnings ?? [] {
            let why = e.time == "amc" ? "After the close" : e.time == "bmo" ? "Before the open" : "Time not set"
            dated.append((e.date, CouponData(d: R.day(e.date), chip: "EARN", title: "\(e.ticker) reports earnings", why: why)))
        }
        for m in u.market ?? [] {
            let why = m.kind == "closed" ? "Market closed"
                : "Market closes at \(MarketClock.clock(MarketClock.closeMinutes(m.date, [CalendarDay(date: m.date, kind: m.kind, closes: m.closes, name: m.name)])))"
            dated.append((m.date, CouponData(d: R.day(m.date), chip: "MARKET", title: m.name, why: why)))
        }
        for m in u.macro ?? [] {
            let t = (m.time ?? "").split(separator: ":").compactMap { Int($0) }
            let why = t.count >= 2 ? "\(MarketClock.clock(t[0] * 60 + t[1])) ET" : "Time not set"
            dated.append((m.date, CouponData(d: R.day(m.date), chip: "MACRO", title: m.name, why: why)))
        }
        for x in u.exDividend ?? [] {
            let why = (x.callsSold ?? 0) > 0 ? "Your \(x.callsSold!) calls sold could be assigned early"
                : x.amount.map { "\(F.money($0, cents: true)) a share" } ?? "Dividend declared"
            dated.append((x.date, CouponData(d: R.day(x.date), chip: "EX-DIV", title: "\(x.ticker) goes ex-dividend", why: why)))
        }
        var out = dated.sorted { $0.0 < $1.0 }.map(\.1)
        for l in (u.longs ?? []).sorted(by: { $0.expiry < $1.expiry }) {
            guard let p = R.leg(l.leg) else { continue }
            let month = p.month.prefix(1) + p.month.dropFirst().lowercased()
            let why: String
            if let s = l.sinceBoughtPct { why = s == 0 ? "Flat since bought" : "\(s > 0 ? "Up" : "Down") \(Int(abs(s)))% since bought" }
            else { why = "Not marked yet" }
            out.append(CouponData(d: "\(l.months) MO", chip: "LEAP", title: "\(p.ticker) \(month) \(p.call ? "call" : "put")", why: why))
        }
        return out
    }
}

struct DoubleRule: View {
    var body: some View {
        VStack(spacing: 1) {
            Rectangle().fill(S.receiptInk).frame(height: 1)
            Rectangle().fill(S.receiptInk).frame(height: 1)
        }
    }
}

/// ★ BEST ★ stamped on when Best opens.
struct BestStamp: View {
    let sub: String
    let shown: Bool
    @State private var on = false
    var body: some View {
        VStack(spacing: 2) {
            Text("★ BEST ★").sMono(18, 700, line: 18, tracking: 0.1)
            Text(sub).sMono(11, 400, line: 13, tracking: 0.16)
        }
        .foregroundStyle(S.receiptRed)
        .padding(.vertical, 8).padding(.horizontal, 12)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(S.receiptRed, lineWidth: 3))
        .blendMode(.multiply)
        .rotationEffect(.degrees(-12))
        .scaleEffect(on ? 1 : 2.4)
        .opacity(on ? 1 : 0)
        .onAppear {
            withAnimation(.timingCurve(0.34, 1.4, 0.4, 1, duration: 0.28).delay(0.35)) { on = true }
        }
        .accessibilityHidden(true)
    }
}

struct Coupon: View {
    let c: ReportPaper.CouponData
    let clipped: Bool
    let onClip: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(c.d).sMono(14, 700, line: 18).lineLimit(1).fixedSize()
                Text(c.chip).sMono(11, 700, line: 12, tracking: 0.08).foregroundStyle(S.receiptMuted)
            }
            .frame(minWidth: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title).sMono(12, 700, line: 15)
                Text(c.why).sMono(11, line: 14).foregroundStyle(S.receiptNote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClip) {
                Text(clipped ? "CLIPPED" : "✂ CLIP").sMono(11, 700, line: 11, tracking: 0.06)
                    .foregroundStyle(clipped ? Color.white : S.receiptInk)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 64, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 6).fill(clipped ? S.receiptInk : Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(S.receiptInk, lineWidth: 1.5))
            }
            .buttonStyle(SPressStyle())
            .accessibilityLabel(clipped ? "Clipped" : "Clip")
        }
        .foregroundStyle(S.receiptInk)
        .padding(.vertical, 10).padding(.leading, 12).padding(.trailing, 8)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(S.receiptInk, style: StrokeStyle(lineWidth: 2, dash: clipped ? [] : [6, 4])))
    }
}

// MARK: - Theta check (block 07)

struct ThetaPaper: View {
    let check: Deck.ThetaCheck
    let calendar: [CalendarDay]
    @State private var why = true
    @State private var roll = true
    @State private var details = DebugPreset.string("rcpt.open") == "all"

    var body: some View {
        let leg = R.leg(check.leg)
        let r = check.roll
        VStack(alignment: .leading, spacing: 0) {
            ReceiptMasthead(kind: "THETA CHECK")
            VStack(spacing: 10) {
                if let leg {
                    Text("\(leg.ticker) · \(leg.month) $\(leg.strike) \(leg.call ? "CALLS" : "PUTS")")
                        .sMono(12, 700, line: 14, tracking: 0.16)
                }
                // Balanced like the design's headline: thin, then bold from the name.
                let thin = "It’s time to roll the ", whole = thin + "\(check.ticker) long calls."
                let set = Array(SWrap.lines(whole, font: SMono(size: 28).uiFont(), kern: -0.28, width: 300, .balance))
                (Text(String(set.prefix(thin.count))) + Text(String(set.dropFirst(thin.count))).font(Font(SMono(size: 28, weight: 700).uiFont())))
                    .sMono(28, 400, line: 34, tracking: -0.01)
                    .multilineTextAlignment(.center)
                    .fixedSize()
                if let now = check.ratioNow {
                    HStack(spacing: 0) {
                        Text("THETA ")
                        Text("\(F.level(now))×").foregroundStyle(S.receiptRed)
                        // "Back to" only when the roll lifts the book (KR's would have lowered it).
                        if let after = r?.bookRatio?.after { Text(" · \(after > now ? "BACK TO " : "")\(F.level(after))× AFTER") }
                    }
                    .sMono(11, line: 14, tracking: 0.04).foregroundStyle(S.receiptMuted)
                }
            }
            .foregroundStyle(S.receiptInk)
            .frame(maxWidth: .infinity)
            .padding(.top, 36).padding(.bottom, 28)
            DoubleRule()

            ReceiptFold(label: "WHY", value: check.trigger == "growth" ? "LOSING FASTER" : "PULLS THE BOOK DOWN", open: $why) {
                ReceiptNote(text: whyText)
            }
            if let r, r.error == nil, let c = r.close, let o = r.open {
                ReceiptFold(label: "THE ROLL", value: "\(c.contracts) CONTRACTS", open: $roll) {
                    VStack(alignment: .leading, spacing: 0) {
                        ReceiptLeader(name: "CLOSE", how: R.short(c.expiry, c.strike), value: "\(c.contracts)")
                        ReceiptLeader(name: "OPEN", how: R.short(o.expiry, o.strike), value: "\(o.contracts)")
                        let debit = r.netDebit ?? 0
                        ReceiptLeader(name: debit >= 0 ? "NET DEBIT" : "NET CREDIT", value: R.f2(debit),
                                      valueColor: debit > 0 ? S.receiptRed : S.receiptInk)
                        ReceiptLeader(name: "COMMISSION + FEES", value: R.f2(r.commissionFees ?? 0), valueColor: S.receiptRed)
                    }
                    .padding(.bottom, 16)
                }
                ReceiptFold(label: "DETAILS", value: "OLD → NEW", valueColor: S.receiptMuted, last: true, open: $details) {
                    VStack(alignment: .leading, spacing: 0) {
                        pair("THETA / DAY", r.thetaDay) { F.money($0).dropFirst().description }
                        pair("TIME VALUE LEFT", r.timeValueLeft) { F.money($0).dropFirst().description }
                        pair("IV", r.iv) { F.pct($0 * 100, places: 1) }
                        pair("DELTA", r.delta) { F.level($0) }
                        pair("OPEN INTEREST", r.openInterest) { F.money($0).dropFirst().description }
                    }
                    .padding(.bottom, 16)
                }
            } else {
                ReceiptFold(label: "THE ROLL", value: "NOT PRICED", valueColor: S.receiptMuted, last: true, open: $roll) {
                    ReceiptNote(text: "NO LATER EXPIRY COULD BE PRICED TONIGHT. IT TRIES AGAIN AFTER THE NEXT CLOSE.")
                }
            }
            ReceiptFoot(line: "CHECKED EVERY CLOSE · NEXT \(R.weekdayDay(MarketClock.nextTrading(after: check.foundOn, calendar).iso))")
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(S.receiptInk)
    }

    @ViewBuilder private func pair(_ name: String, _ p: Deck.ThetaCheck.Roll.Pair?, _ f: (Double) -> String) -> some View {
        if let p, let n = p.new {
            ReceiptLeader(name: name, old: p.old.map(f) ?? "-", value: f(n))
        }
    }

    private var whyText: String {
        var s = ""
        if let now = check.thetaNow {
            s = "LOSING \(F.money(now)) A DAY"
            if let then = check.thetaThen, then > 0 {
                let x = now / then
                s += x >= 1.9 && x < 2.1 ? ", TWICE WHAT THEY LOST A MONTH AGO."
                    : ", UP \(Int(((x - 1) * 100).rounded()))% ON A MONTH AGO."
            } else { s += "." }
        }
        if let w = check.ratioWithout, let now = check.ratioNow, w > now {
            s += " THAT ALONE PULLS THETA FROM \(F.level(w))× DOWN TO \(F.level(now))×."
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
