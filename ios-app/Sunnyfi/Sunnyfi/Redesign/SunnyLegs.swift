//
//  SunnyLegs.swift
//  Sunny — the P&L legs widget. cards/position-legs.md is normative.
//
//  ⚠ ONE KIND OF NUMBER ON EVERY CARD. The widget shipped once with three kinds
//  of figure on four cards: P&L on shares, credit received on the sold legs,
//  debit paid on the bought ones. The four never summed to the header and a
//  percentage could not be added, because every card's denominator differed.
//  Mark to market on every leg, and one percentage rule: P&L over cash
//  committed. The server owns that arithmetic; this file only draws it.
//
//  ⚠ NO EMPTY CELL, EVER. The PARITY of the option-leg count picks the layout,
//  because that is what decides whether the cards fill whole rows. Even legs put
//  shares on an M so the rows square off; odd makes shares an S and it joins the
//  run as its first card. Shares does not "get the M" — it takes the M only when
//  that squares the grid.
//
//  ⚠ THE REVEAL IS A CLIP, NOT A RESIZE. The first build animated the card's box
//  and it felt jerky for a reason worth keeping written down: the card has
//  fifteen absolutely positioned descendants and animating its box relaid every
//  one of them out on every frame. The card is permanently 361 x 361 and is
//  revealed by an animatable inset. Two things fall out — the radius stays
//  literally 22 at every frame, where a scale from 175 would drag it to 45 and
//  soften every glyph; and the content never reflows, because the element it
//  lives in never changes size.
//

import SwiftUI

// MARK: - the model, as position-legs sends it

struct LegsPosition: Decodable, Identifiable {
    let ticker: String
    let spot: Double
    let shares: Shares
    let legs: [Leg]
    let total: Int
    var id: String { ticker }

    struct Shares: Decodable {
        let label: String
        let pnl: Int
        let pct: Double
        let basis: Int
        let contract: String
        let market: Int
    }
    struct Leg: Decodable, Identifiable {
        let code: String        // PS · CS · PB · CB
        let label: String
        let short: Bool
        let pnl: Int
        let pct: Double
        let committed: Int
        let value: Int
        let contracts: Double
        let contract: String
        /// Days to the NEAREST expiry when a code rolls up several: the
        /// sub-label says how long you are exposed, and that is decided by the
        /// leg which resolves first.
        let dte: Int
        var id: String { code }
    }
}

@Observable
final class LegsStore {
    var positions: [LegsPosition] = []
    var error: String?
    private var loading = false

    func load() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/position-legs") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 45
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Secrets.supabasePublishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(Secrets.supabasePublishableKey)", forHTTPHeaderField: "Authorization")
        r.httpBody = Data("{}".utf8)
        do {
            let (d, resp) = try await URLSession.shared.data(for: r)
            if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { error = "HTTP \(h.statusCode)"; return }
            positions = try JSONDecoder().decode(LegsPayload.self, from: d).positions ?? []
        } catch { self.error = String(describing: error) }
    }
}

private struct LegsPayload: Decodable { var positions: [LegsPosition]? }

// MARK: - layout: the parity rule, in one place

/// One drawn card: which leg it is, and the rect it occupies in the region.
struct LegSlot: Identifiable {
    let code: String            // "SH" or a leg code
    let rect: CGRect
    var id: String { code }
    var isM: Bool { rect.width > S.legCard }
}

enum LegsLayout {
    /// ⚠ THE CLIENT MUST NOT RE-DERIVE THE PARITY. The server sends `layout`,
    /// but the RECTS are geometry and belong here — they are what the clip and
    /// the figure travel are computed from, and a second opinion about where a
    /// card sits is how the shadow ends up under the wrong cell.
    static func slots(_ p: LegsPosition) -> [LegSlot] {
        let n = p.legs.count
        var out: [LegSlot] = []
        let even = n % 2 == 0
        if even {
            out.append(LegSlot(code: "SH", rect: CGRect(x: 0, y: 0, width: S.content, height: S.sharesMH)))
            for (i, l) in p.legs.enumerated() {
                out.append(LegSlot(code: l.code, rect: CGRect(
                    x: CGFloat(i % 2) * S.regionRow,
                    y: S.regionMOffset + CGFloat(i / 2) * S.regionRow,
                    width: S.legCard, height: S.legCard)))
            }
        } else {
            // Shares is an S and joins the run as its first card, which is what
            // makes the total even and the rows whole.
            let all = ["SH"] + p.legs.map(\.code)
            for (i, c) in all.enumerated() {
                out.append(LegSlot(code: c, rect: CGRect(
                    x: CGFloat(i % 2) * S.regionRow,
                    y: CGFloat(i / 2) * S.regionRow,
                    width: S.legCard, height: S.legCard)))
            }
        }
        return out
    }

    static func gridHeight(_ p: LegsPosition) -> CGFloat {
        let n = p.legs.count
        if n % 2 == 0 {
            let r = CGFloat(max(1, n / 2))
            return S.regionMOffset + r * S.legCard + (r - 1) * S.gutter
        }
        let r = CGFloat((n + 1) / 2)
        return r * S.legCard + (r - 1) * S.gutter
    }
}

// MARK: - the region

struct SunnyLegsRegion: View {
    let p: LegsPosition

    /// nil = the grid. Non-nil = the code the card was opened ON, which is only
    /// used for the opening clip; `active` is what the card is showing.
    @State private var open: String?
    @State private var active = "SH"
    /// ⚠ HEIGHT KEYS OFF `grown`, NEVER OFF `open`. `open` clears only after the
    /// 420ms lock, so keying height off it leaves the region tall for the whole
    /// shrink and then grows it in a SECOND pass — measured at ~840ms to settle,
    /// with the bottom row painting 140px over the section below on the way.
    @State private var grown = false
    @State private var busy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var slots: [LegSlot] { LegsLayout.slots(p) }
    private func slot(_ code: String) -> LegSlot {
        slots.first { $0.code == code } ?? slots[0]
    }
    /// Collapsing targets the ACTIVE tab's cell, not the one you opened. Open
    /// Shares, tab across to CB, close, and the card shrinks into CB's cell —
    /// which is where your eye already is.
    private var target: LegSlot { slot(open == nil ? active : (grown ? active : open!)) }

    /// Verification only: the touch bridge cannot inject a tap in this session,
    /// so this opens the region on a named tab a beat after it appears. It goes
    /// through `expand`, the same function the tap calls, so the lock, the clock
    /// and the clip are all exercised — only UIKit delivering the touch is not.
    private static var argOpen: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-legsOpen"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. the grid. It does not MOVE as it leaves: the cards fade where
            //    they sit, and the picked one needs no fade of its own because
            //    the detail card materialises over it opaque before anything moves.
            ForEach(slots) { s in
                card(s)
                    .frame(width: s.rect.width, height: s.rect.height)
                    .offset(x: s.rect.minX, y: s.rect.minY)
                    .opacity(grown ? 0 : 1)
                    .scaleEffect(grown ? S.zoomScale : 1)
                    .allowsHitTesting(!grown)
            }

            if open != nil || grown {
                // 2. the shadow is its own leaf. A clip clips a box-shadow away,
                //    so it cannot live on the card. Lighter when small: scaling
                //    tightens the blur, which is what a smaller card really does.
                RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous)
                    .fill(S.paper)
                    .frame(width: S.detailSide, height: S.detailSide)
                    .sunnyShadow(S.shadowCardL)
                    .scaleEffect(x: grown ? 1 : target.rect.width / S.detailSide,
                                 y: grown ? 1 : target.rect.height / S.detailSide,
                                 anchor: .topLeading)
                    .offset(x: grown ? 0 : target.rect.minX,
                            y: grown ? 0 : min(target.rect.minY, S.regionRow))
                    .opacity(grown ? 1 : S.zoomShadowSmall)

                // 3. the card, revealed by an animatable inset. Never resized.
                SunnyLegsDetail(p: p, active: $active, onBack: collapse,
                                travel: grown ? nil : figTravel(target))
                    .frame(width: S.detailSide, height: S.detailSide)
                    .background(S.paper)
                    .clipShape(LegsReveal(inset: grown ? EdgeInsets() : insets(for: target),
                                          radius: S.radiusCard))
                    .opacity(grown ? 1 : 0)
                    .animation(S.easeOut(grown ? S.durZoomIn : S.durZoomOut)
                        .delay(grown ? S.zoomContentDelay : 0), value: grown)
            }
        }
        .frame(width: S.content, height: grown ? S.detailSide : LegsLayout.gridHeight(p),
               alignment: .topLeading)
        // The one layout animation in the widget, and it is safe here for a
        // specific reason: every child of the region is absolutely positioned,
        // so the region's height reflows nothing inside it. Only the feed below
        // slides.
        .animation(reduceMotion ? .easeInOut(duration: S.durZoomIn) : S.easeSettle(S.durZoom),
                   value: grown)
        .measure("legs-region-\(p.ticker)")
        .task {
            guard let code = Self.argOpen else { return }
            try? await Task.sleep(for: .seconds(3))
            expand(code)
        }
    }

    /* ⚠ THE FIGURE IS THE ONE ELEMENT THAT TRAVELS, and it is rendered at 34
       and scaled DOWN so the resting state is native-crisp. The LABEL does not
       travel: a tab's x depends on the width of every tab before it, which is
       unmeasurable at author time, so the strip fades in as a unit with the
       tapped leg already inked. The number carries the continuity, and the
       number is the right element to carry it — it is what the eye was on. */
    private func figTravel(_ s: LegSlot) -> CGSize {
        CGSize(width: (s.isM ? S.figL : s.rect.minX + S.figS) - S.figL,
               height: s.rect.minY + S.figSY - S.figLY)
    }

    /// grown inset is zero; from a cell it is the cell's own rect, with the
    /// bottom row clamped to a sliver so a row below the card's 361 box still
    /// has a legal origin in the correct column.
    private func insets(for s: LegSlot) -> EdgeInsets {
        EdgeInsets(top: min(s.rect.minY, S.detailSide - 2),
                   leading: s.rect.minX,
                   bottom: max(0, S.detailSide - s.rect.minY - s.rect.height),
                   trailing: S.detailSide - s.rect.minX - s.rect.width)
    }

    // MARK: the grid cards

    @ViewBuilder
    private func card(_ s: LegSlot) -> some View {
        Group {
            if s.code == "SH" {
                SunnyLegCard(label: p.shares.label, pnl: p.shares.pnl,
                             sub: pctLabel(p.shares.pct, of: "on cost"),
                             line1: p.shares.contract,
                             line2: "Market $\(money(p.shares.market))",
                             wide: s.isM)
            } else if let leg = p.legs.first(where: { $0.code == s.code }) {
                SunnyLegCard(label: leg.label, pnl: leg.pnl,
                             sub: leg.short ? "\(Int(leg.pct.rounded()))% CAPTURED"
                                            : pctLabel(leg.pct, of: "on debit"),
                             line1: leg.contract,
                             line2: "Now worth $\(money(leg.value))",
                             wide: s.isM)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { expand(s.code) }
    }

    // MARK: the clock

    private func expand(_ code: String) {
        guard !busy else { return }          // a double tap must not open and close in one breath
        busy = true
        active = code
        open = code
        if reduceMotion { grown = true } else {
            // Two frames, so the clip starts from the cell rather than from zero.
            DispatchQueue.main.async { grown = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + S.zoomLock) { busy = false }
    }

    private func collapse() {
        guard !busy else { return }
        busy = true
        grown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + S.zoomLock) {
            open = nil; busy = false
        }
    }
}

/// The reveal. An inset rounded rect whose corner radius never changes, which is
/// the entire reason this is a clip and not a scale.
/* ⚠ `nonisolated` IS LOAD-BEARING. This target compiles with default main-actor
   isolation, so a bare struct here gets a main-actor-isolated Animatable
   conformance — and Shape requires Self: Sendable, which a main-actor
   conformance cannot satisfy. The error names Animatable, not Shape, which is
   what makes it confusing. The whole type is nonisolated; nothing in it touches
   the actor. */
nonisolated struct LegsReveal: Shape, Animatable {
    var inset: EdgeInsets
    /* ⚠ THE RADIUS IS PASSED IN, NOT READ FROM S INSIDE path(in:). A Shape's
       path is nonisolated, and under Swift 6 a static on S is main-actor
       isolated, so reaching for the token in here makes the whole conformance
       main-actor and Shape stops being satisfiable. The call site is a view
       body, which IS on the main actor, so the token is still the source. */
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>,
                                       AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(inset.top, inset.leading), .init(inset.bottom, inset.trailing)) }
        set {
            inset = EdgeInsets(top: newValue.first.first, leading: newValue.first.second,
                               bottom: newValue.second.first, trailing: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        let box = CGRect(x: inset.leading, y: inset.top,
                         width: max(0, rect.width - inset.leading - inset.trailing),
                         height: max(0, rect.height - inset.top - inset.bottom))
        return Path(roundedRect: box, cornerRadius: radius, style: .continuous)
    }
}

// MARK: - a grid card, S or M

struct SunnyLegCard: View {
    let label: String
    let pnl: Int
    let sub: String
    let line1: String
    let line2: String
    let wide: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            S.paper
            // Absolute y, per §3 and §4. The figure and sub-label sit at the
            // SAME y on both sizes (52 and 89) so the travel maths is one rule.
            Text(label)
                .font(InkFont.display(S.t10, S.wBold))
                .tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
                .offset(x: padX, y: wide ? 17 : 16)
            Text(signed(pnl))
                .font(InkFont.display(S.t30, S.wSemi))
                .tracking(S.track(S.t30, -0.035))
                .foregroundStyle(pnl >= 0 ? S.gain : S.loss)
                .monospacedDigit()
                .offset(x: padX, y: S.figSY)
            // The 7 above this is a fix, not a choice: it shipped at 2 and a
            // 10px label 2px under a 30px figure reads as one clotted block.
            Text(sub)
                .font(InkFont.display(S.t10, S.wBold))
                .tracking(S.track(S.t10, S.lsLabel))
                .foregroundStyle(S.mute)
                .offset(x: padX, y: S.subSY)
            footer
        }
        .frame(width: wide ? S.content : S.legCard, height: wide ? S.sharesMH : S.legCard,
               alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: S.radiusCard, style: .continuous))
        .sunnyShadow(S.shadowCard)
    }

    private var padX: CGFloat { wide ? S.figL : S.figS }

    /* Footer bolding is ONE rule, not scattered emphasis: line 1 is the
       contract in --mute-2 500, line 2 is the live number in --ink 600. An
       earlier version bolded individual digits inside both lines, which made
       neither line read as the important one.

       The M turns the same left-mute / right-ink logic 90 degrees: it has the
       width for two columns rather than two lines. */
    @ViewBuilder
    private var footer: some View {
        if wide {
            HStack(spacing: S.gap6) {
                Text(line1)
                    .font(InkFont.display(S.t12, S.wMid)).foregroundStyle(S.mute2)
                Spacer(minLength: 0)
                Text(line2)
                    .font(InkFont.display(S.t12, S.wSemi)).foregroundStyle(S.ink)
            }
            .monospacedDigit()
            .frame(width: S.content - S.figL * 2, alignment: .leading)
            .offset(x: S.figL, y: 141)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(line1)
                    .font(InkFont.display(S.t12, S.wMid)).foregroundStyle(S.mute2)
                    .frame(height: 17)
                Text(line2)
                    .font(InkFont.display(S.t12, S.wSemi)).foregroundStyle(S.ink)
                    .frame(height: 17)
            }
            .monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(width: S.legCard - S.figS * 2, alignment: .leading)
            .offset(x: S.figS, y: 125)
        }
    }
}

// MARK: - formatting

func signed(_ v: Int) -> String {
    (v < 0 ? "\u{2212}" : "+") + "$" + abs(v).formatted(.number.grouping(.automatic))
}
func money(_ v: Int) -> String { abs(v).formatted(.number.grouping(.automatic)) }
func pctLabel(_ v: Double, of what: String) -> String {
    let sign = v < 0 ? "\u{2212}" : ""
    return "\(sign)\(abs(v).formatted(.number.precision(.fractionLength(1))))% \(what.uppercased())"
}

// MARK: - the detail card, 361 × 361

/// ⚠ THE TAB STRIP CARRIES CODES, SO THE SUB-LABEL MUST ALWAYS SPELL THE LEG
/// OUT. PS / CS / PB / CB are only legible because the words sit under the
/// figure. Five full names measure ~297 against 323 of strip; codes measure 101.
/// If a future layout drops the leg name from the sub-label, the codes go back
/// to words.
struct SunnyLegsDetail: View {
    let p: LegsPosition
    @Binding var active: String
    let onBack: () -> Void
    /// Nil once grown. Non-nil is the offset from the detail's own figure slot
    /// back to the cell the card is growing out of.
    var travel: CGSize?

    private var tabs: [String] { ["SH"] + p.legs.map(\.code) }
    private var leg: LegsPosition.Leg? { p.legs.first { $0.code == active } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            header.offset(x: S.figL, y: 17)
            strip.offset(x: S.figL, y: 51)
            figure
                .scaleEffect(travel == nil ? 1 : S.zoomFigScale, anchor: .topLeading)
                .offset(x: S.figL + (travel?.width ?? 0),
                        y: S.figLY + (travel?.height ?? 0))
            subLabel.offset(x: S.figL, y: S.subLY)
            rows.offset(x: S.figL, y: 163)
            footer.offset(x: S.figL, y: 310)
        }
        .frame(width: S.detailSide, height: S.detailSide, alignment: .topLeading)
    }

    // 5.1 — the header is the card's constant chrome, and a way back belongs there

    private var header: some View {
        HStack(spacing: S.gap5) {
            /* The back glyph DRAWS THE GRID IT RETURNS YOU TO, so it carries no
               label. Two earlier attempts are on record: the active tab as the
               only collapse control (invisible — the first user could not find
               the way back), then a glyph at the right end of the strip (no room
               once the labels changed). Tapping the active tab still collapses,
               as a shortcut, never as the only way. */
            Button(action: onBack) {
                VStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: 3) {
                            ForEach(0..<2, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: S.radiusPip)
                                    .fill(S.mute2).frame(width: 7, height: 7)
                            }
                        }
                    }
                }
                .frame(width: S.hitMin, height: S.hitMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -S.hitBleed)
            .padding(.leading, -S.hitBleed)

            HStack(alignment: .firstTextBaseline, spacing: S.gap4) {
                Text(p.ticker)
                    .font(InkFont.display(S.t14, S.wBold))
                    .tracking(S.track(S.t14, -0.01))
                    .foregroundStyle(S.ink)
                Text("position P&L")
                    .font(InkFont.display(S.t12, S.wMid))
                    .foregroundStyle(S.mute)
            }
            Spacer(minLength: 0)
            Text(signed(p.total))
                .font(InkFont.display(S.t19, S.wSemi))
                .tracking(S.track(S.t19, -0.025))
                .foregroundStyle(S.totalInk)
                .monospacedDigit()
        }
        .frame(width: S.content - S.figL * 2, alignment: .leading)
    }

    // 5.2 — one tab per leg, and the strip is the grid unwrapped

    private var strip: some View {
        HStack(spacing: 14) {
            ForEach(tabs, id: \.self) { code in
                VStack(spacing: S.gap4) {
                    Text(code == "SH" ? "Shares" : code)
                        .font(InkFont.display(S.t12, code == active ? S.wSemi : S.wMid))
                        .tracking(S.track(S.t12, -0.005))
                        .foregroundStyle(code == active ? S.ink : S.mute2)
                        .frame(height: S.t12)
                    RoundedRectangle(cornerRadius: S.rule)
                        .fill(code == active ? S.ink : .clear)
                        .frame(height: S.ruleHeavy)
                }
                .fixedSize()
                .contentShape(Rectangle())
                // Tapping the ACTIVE tab collapses — the shortcut, not the only way.
                .onTapGesture { if code == active { onBack() } else { active = code } }
            }
            Spacer(minLength: 0)
        }
        .frame(width: S.content - S.figL * 2, height: 22, alignment: .leading)
    }

    // 5.3 — the figure travels; the sub-label always names the leg

    private var value: Int { leg?.pnl ?? p.shares.pnl }

    private var figure: some View {
        Text(signed(value))
            .font(InkFont.display(S.t34, S.wSemi))
            .tracking(S.track(S.t34, -0.04))
            .foregroundStyle(value >= 0 ? S.gain : S.loss)
            .monospacedDigit()
    }

    private var subLabel: some View {
        Text(subText)
            .font(InkFont.display(S.t12, S.wMid))
            .foregroundStyle(S.mute)
            .monospacedDigit()
    }

    /* ⚠ SENTENCE CASE, AND IT ALWAYS NAMES THE LEG. `.capitalized` gave "Puts
       Sold", which is a headline, not a label — the sheet's table reads "Puts
       sold · 34% captured · 26d" throughout. And the words are not decoration:
       §0.4 says the tab strip may carry codes ONLY because the leg is spelled
       out here. Drop the name and the codes go back to words. */
    private var subText: String {
        guard let l = leg else {
            return "Unrealised · \(fmtPct(p.shares.pct)) on cost"
        }
        let name = l.label.prefix(1) + l.label.dropFirst().lowercased()
        return l.short
            ? "\(name) · \(Int(l.pct.rounded()))% captured · \(l.dte)d"
            : "\(name) · \(fmtPct(l.pct)) on debit · \(l.dte)d"
    }

    // 5.4 — the body band. Shares has two rows, every option leg three.

    private var rows: some View {
        VStack(spacing: S.gap4 + 1) {
            ForEach(Array(rowData.enumerated()), id: \.offset) { i, r in
                if i > 0 { Rectangle().fill(S.wash).frame(height: S.rule) }
                HStack(alignment: .firstTextBaseline, spacing: S.gap6) {
                    Text(r.0)
                        .font(InkFont.display(S.t13, S.wMid)).foregroundStyle(S.mute2)
                    Spacer(minLength: 0)
                    Text(r.1)
                        .font(InkFont.display(S.t14, S.wSemi)).foregroundStyle(S.ink)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: S.content - S.figL * 2, height: S.bandH, alignment: .top)
    }

    private var rowData: [(String, String)] {
        guard let l = leg else {
            return [("Cost", "$\(money(p.shares.basis))"),
                    ("Market at \(p.spot.formatted(.number.precision(.fractionLength(2))))",
                     "$\(money(p.shares.market))")]
        }
        return [(l.contract, ""),
                (l.short ? "Credit taken" : "Debit paid", "$\(money(l.committed))"),
                ("Now worth", "$\(money(l.value))")]
    }

    // 5.5 — one sentence, and it changes with the leg

    private var footer: some View {
        Text(footerText)
            .font(S.inter(12.5, S.wBodyN))
            .lineSpacing(S.leading(12.5, S.wBodyN, S.lhBody))
            .foregroundStyle(S.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: S.content - S.figL * 2, alignment: .leading)
    }

    private var footerText: String {
        guard let l = leg else {
            return p.shares.pnl >= 0
                ? "The block is above cost. Premium is what the position earns; this is the base it earns on."
                : "The block is below cost. The premium and the floor are what carry it until it is not."
        }
        if l.short {
            return l.pnl >= 0
                ? "\(Int(l.pct.rounded()))% of the credit has decayed. Closing it now costs $\(money(l.value))."
                : "It costs more to close than it paid. Assignment is the plan, not the accident."
        }
        return "Paid $\(money(l.committed)) for this cover, worth $\(money(l.value)) now. It is insurance, not a trade."
    }

    private func fmtPct(_ v: Double) -> String {
        (v < 0 ? "\u{2212}" : "") + abs(v).formatted(.number.precision(.fractionLength(1))) + "%"
    }
}
