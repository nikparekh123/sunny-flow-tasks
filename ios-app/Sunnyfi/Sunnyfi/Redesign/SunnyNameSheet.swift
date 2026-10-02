//
//  SunnyNameSheet.swift
//  A name's detail (Nik, 28 Sep 2026: "open ticker when clicked on it to show
//  details about what is open Bought, Sold and Closed"). Tap a ticker on the
//  Book and one glass panel rises from the screen's edge, the roll sheet's
//  presentation: what is bought and still open, what is sold and still open,
//  and every long leg closed since the book began with what it realized.
//
//  ⚠ CLOSED IS IBKR'S NUMBER WHERE IT HAS ONE. The 09:00 Daily Flex carries
//  IBKR's realized on each closing fill; until it lands, the figure is average
//  cost, IBKR's own method on this account, and the row says "est".
//

import SwiftUI

// MARK: - payload

struct ClosedCard: Decodable {
    let since: String
    let names: [String: ClosedName]
}

struct ClosedName: Decodable {
    /// Realized on long calls and long puts sold back, dollars.
    let calls: Int, puts: Int
    let legs: [ClosedLeg]
    var total: Int { calls + puts }
}

struct ClosedLeg: Decodable, Identifiable {
    /// `37.5P` · `30C`
    let k: String
    let exp: String
    let n: Int
    /// Average cost and average sale, dollars a contract.
    let avg: Double, px: Double
    let rz: Int
    /// The last close's date.
    let d: String
    /// `ibkr` · `avg` · `mixed`
    let src: String
    var id: String { "\(k)|\(exp)" }
}

// MARK: - the sheet

struct SunnyNameSheet: View {
    let t: String
    let spot: Double?
    let legs: [LongLeg]
    let shorts: [OptionsPosition.ShortLeg]
    let closed: ClosedName?
    let intrinsic: IntrinsicRow?
    /// Short-leg credit kept (settled) and taken on legs still open, dollars.
    let banked: Int, openCredit: Int
    let onClose: () -> Void

    private static let inner: CGFloat = 301
    /// The lists' own height: the scroll area hugs it, up to 440.
    @State private var listH: CGFloat = 0

    private func day(_ iso: String, _ fmt: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        f.dateFormat = fmt
        return f.string(from: d)
    }
    private func px(_ v: Double) -> String { String(format: "%.2f", v) }
    private func money(_ v: Double) -> String { signedMoney(v) }

    /// Mark against average cost on the legs still held.
    private var atMark: Double { legs.reduce(0) { $0 + ($1.m - $1.cost) * Double($1.n) } }
    private var net: Double { Double(banked) + atMark + Double(closed?.total ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(S.hair).frame(width: 36, height: 4)
                .frame(width: 44, height: 16, alignment: .top)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle()).onTapGesture(perform: onClose)
            Spacer().frame(height: 12)
            (Text(t).font(S.inter(S.t13, S.wSemiN)).foregroundStyle(S.ink)
             + Text(spot.map { " is \(px($0))" } ?? "").font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute))
                .lineLimit(1)
            Spacer().frame(height: 10)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(money(net)).font(S.inter(34, S.wBoldN)).tracking(S.track(34, -0.03))
                    .foregroundStyle(net < 0 ? S.lossText : S.gainText).sunnyLineBox(34)
                Text("net since 31 Aug").font(S.inter(15, S.wMidSmN)).foregroundStyle(S.mute)
            }
            .lineLimit(1)
            Spacer().frame(height: 6)
            Text("banked \(optMoney(banked)) \u{00B7} closed \(money(Double(closed?.total ?? 0))) \u{00B7} at mark \(money(atMark))")
                .font(S.inter(S.t13, S.wMidSmN)).foregroundStyle(S.mute).lineLimit(1).minimumScaleFactor(0.85)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    section("Bought \u{00B7} open", note: legs.isEmpty ? "none" : "cost \u{2192} now") {
                        ForEach(legs) { l in
                            let exp = (l.isCall ? intrinsic?.call?.exp : intrinsic?.put?.exp).map { day($0, "MMM ''yy") } ?? ""
                            row("\(l.n) \u{00D7} \(l.k)", exp, "\(px(l.cost / 100)) \u{2192} \(px(l.m / 100))",
                                (l.m - l.cost) * Double(l.n))
                        }
                    }
                    section("Sold \u{00B7} open", note: shorts.isEmpty ? "none" : "sold \u{2192} now") {
                        ForEach(shorts) { s in
                            let now = s.n > 0 ? Double(s.value) / Double(s.n) / 100 : 0
                            row("\(s.n) \u{00D7} \(s.label)", day(s.exp, "EEE d MMM"),
                                "\(px(s.cr ?? 0)) \u{2192} \(px(now))", Double(s.credit - s.value))
                        }
                        if openCredit > 0 {
                            Text("\(optMoney(openCredit)) of credit on these, not yet banked")
                                .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                        }
                    }
                    section("Closed", note: (closed?.legs.isEmpty ?? true) ? "none" : "avg cost \u{2192} sold") {
                        ForEach(closed?.legs ?? []) { c in
                            row("\(c.n) \u{00D7} \(c.k)", day(c.d, "d MMM") + (c.src == "ibkr" ? "" : " \u{00B7} est"),
                                "\(px(c.avg / 100)) \u{2192} \(px(c.px / 100))", Double(c.rz))
                        }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listH = $0 }
            }
            /* ⚠ A SCROLL VIEW TAKES ALL THE HEIGHT IT IS OFFERED, so a short
               name left a white slab under its last row. It is sized to the
               lists, and scrolls only past 440. */
            .frame(height: min(max(listH, 1), 440))
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: Self.inner, alignment: .leading)
        .padding(EdgeInsets(top: 8, leading: 22, bottom: 24, trailing: 22))
        .frame(maxWidth: .infinity, alignment: .top)
        .glassEffect(.regular.tint(S.rsGlassTint), in: .rect(cornerRadius: 40, style: .continuous))
        .shadow(color: S.rsShadow1, radius: 16, x: 0, y: 12)
        .shadow(color: S.rsShadow2, radius: 3, x: 0, y: 2)
        .monospacedDigit()
    }

    @ViewBuilder private func section<C: View>(_ title: String, note: String,
                                               @ViewBuilder _ content: () -> C) -> some View {
        Spacer().frame(height: 22)
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(S.inter(S.t11, S.wBoldN)).tracking(S.track(S.t11, 0.1))
                .foregroundStyle(S.mute)
            Spacer(minLength: 8)
            Text(note).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
        }
        .lineLimit(1)
        Spacer().frame(height: 12)
        VStack(alignment: .leading, spacing: 12) { content() }
    }

    /// `60 × 30C  Jan '28` over `12.58 → 10.30`, the P&L on the right.
    private func row(_ order: String, _ when: String, _ prices: String, _ pnl: Double) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(order).font(S.inter(15, S.wBoldN)).tracking(S.track(15, -0.01)).foregroundStyle(S.ink)
                    Text(when).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                }
                Text(prices).font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text(money(pnl)).font(S.inter(S.t15, S.wMidN)).tracking(S.track(S.t15, -0.015))
                .foregroundStyle(pnl < 0 ? S.lossText : S.gainText).lineLimit(1)
        }
    }
}

// MARK: - the host

/// The roll sheet's presentation for any panel: from the screen's edge, 12
/// in on three sides, a film that follows the glass, a tap outside or a drag
/// down to close.
struct GlassSheetHost<Content: View>: View {
    @ViewBuilder let content: (_ close: @escaping () -> Void) -> Content
    let onDismissed: () -> Void
    @State private var up = false
    @State private var drag: CGFloat = 0
    @State private var h: CGFloat = 500
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                S.rsScrim
                    .opacity(up ? max(0, 1 - Double(max(0, drag)) / Double(h)) : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                if up {
                    content(close)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h = max(1, $0) }
                        .offset(y: max(0, drag))
                        .gesture(
                            DragGesture()
                                .onChanged { drag = $0.translation.height }
                                .onEnded { v in
                                    if max(v.translation.height, v.predictedEndTranslation.height) > h * 0.3 {
                                        close()
                                    } else {
                                        withAnimation(S.easeSettle(0.3)) { drag = 0 }
                                    }
                                })
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .offset(y: 12)))
                }
            }
            .frame(width: g.size.width, height: g.size.height + g.safeAreaInsets.bottom, alignment: .bottom)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { withAnimation(reduceMotion ? nil : S.easeSettle(0.32)) { up = true } }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : S.easeSettle(0.32)) { up = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.32)) { onDismissed() }
    }
}
