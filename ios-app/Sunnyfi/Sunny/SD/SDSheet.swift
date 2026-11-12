//
//  SDSheet.swift
//  Sunny
//
//  The SD calculator sheet, "What to sell" (handoff 2026-11-11-sd-whatif-totals README 1, App Explorations 143a,
//  SunnySD.dc.html app card). The SD chip on Positions raises it to half (600 pt showing); the grabber, or a swipe up,
//  takes it full (56 pt from the top, the page dimmed behind, the sheet scrolls); the grabber, a swipe down or a pull
//  past the top takes it back to half. X, a tap on the dim, or a swipe down from half closes it. It lies over the tab
//  bar, as the design's does.
//
//  Top to bottom, as the card: header (ticker, price, today's move, IV · 1 SD, the X), the expiries, the signals
//  (outlined, snap sideways), How many (Sell call and Sell put, a number and the system stepper, both from 0), the
//  strikes (calls then puts in one sideways strip; the dot is the suggestion, ink is what is picked), What the sale
//  does (a sentence, then Held, + New and = Both on one price scale), the Calls and Puts cards, and the foot line.
//  No Try in What if in the app (D2, Nik 11 Nov 2026). The numbers come from SDStore.sale (SDSale, the web's engine).
//

import SwiftUI

/// Over everything on the tabs (HomeView), so it covers the tab bar. Draws nothing while closed.
struct SDSheetHost: View {
    @State private var sd = SDStore.shared
    @AppStorage(BriefPrivacy.key) private var privacy = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// A vertical swipe on the half sheet: the sheet follows the finger, then settles.
    @GestureState(resetTransaction: Transaction(animation: S.standard(0.45))) private var dragY: CGFloat = 0
    /// The content stays while the sheet slides away, then goes.
    @State private var lingering = false
    /// How far the full sheet is pulled past its top.
    @State private var topPull: CGFloat = 0

    /// The full sheet's top, from the top of the screen.
    static let fullTop: CGFloat = 56

    var body: some View {
        GeometryReader { g in
            let ins = g.safeAreaInsets
            let H = g.size.height + ins.top + ins.bottom, W = g.size.width + ins.leading + ins.trailing
            let vis = SDStore.halfVisible(height: H, top: ins.top)
            let base: CGFloat = sd.level == .full ? Self.fullTop : sd.level == .half ? H - vis : H + 16
            // A swipe on the half sheet moves it with the finger, never above the full sheet's top.
            let drag = sd.level == .half ? max(Self.fullTop - base, dragY) : 0
            ZStack(alignment: .top) {
                // The dim: only behind the full sheet (at half the page above stays live).
                SDPal.dim
                    .opacity(sd.level == .full ? 1 : 0)
                    .animation(.easeInOut(duration: 0.35), value: sd.level)
                    .contentShape(Rectangle())
                    .onTapGesture { sd.close() }
                    .allowsHitTesting(sd.level == .full)
                    .accessibilityHidden(true)
                // ⚠ PLACED BY LAYOUT (the top padding), NOT AN OFFSET, and the scroll view keeps its safe area: with
                // .ignoresSafeArea() on it, a sheet near the top grew up into the status bar and its content rode 56 pt
                // high (11 Nov 2026).
                sheet
                    .frame(width: W, height: H - Self.fullTop)
                    .offset(y: drag)
                    .padding(.top, base)
                    .animation(reduce ? nil : S.standard(0.45), value: sd.level)
                    // Reduce Motion: no slide, a fade.
                    .opacity(reduce && sd.level == .closed ? 0 : 1)
                    .animation(S.fade, value: sd.level)
                    .allowsHitTesting(sd.level != .closed)
                    .accessibilityHidden(sd.level == .closed && !lingering)
            }
            .frame(width: W, height: H, alignment: .top)
            .ignoresSafeArea()
        }
        .onChange(of: sd.level) { old, new in
            if new == .closed && old != .closed {
                lingering = true
                Task { try? await Task.sleep(for: .milliseconds(550)); if sd.level == .closed { lingering = false } }
            }
        }
    }

    @ViewBuilder private var sheet: some View {
        let full = sd.level == .full
        ScrollView(.vertical) {
            if sd.level != .closed || lingering {
                SDCard(sd: sd, privacy: privacy)
                    .padding(.bottom, 48)
            }
        }
        .scrollIndicators(.hidden)
        // At half the sheet holds still (a swipe moves the sheet); full, it scrolls, and a scroll puts the keyboard away.
        .scrollDisabled(!full)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, v in topPull = v }
        .onScrollPhaseChange { old, new in
            // A pull down past the top, let go: back to half.
            if full, old == .interacting, new != .interacting, topPull < -64 { sd.setLevel(.half) }
        }
        .background(SDPal.cd)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 36, topTrailingRadius: 36, style: .continuous))
        // 0 -12px 40px rgba(0,0,0,.18)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 36, topTrailingRadius: 36, style: .continuous)
                .fill(SDPal.cd).shadow(color: .black.opacity(0.18), radius: 20, y: -12)
        }
        .simultaneousGesture(swipe, including: full ? .subviews : .all)
        .accessibilityAddTraits(full ? .isModal : [])
        .accessibilityAction(.escape) { sd.close() }
    }

    /// The half sheet: up past 40 pt (or a flick) goes full, down past 90 closes.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .updating($dragY) { v, s, _ in
                if abs(v.translation.height) > abs(v.translation.width) { s = v.translation.height }
            }
            .onEnded { v in
                let dy = v.translation.height, p = v.predictedEndTranslation.height
                guard sd.level == .half, abs(dy) > abs(v.translation.width) else { return }
                if dy < -40 || p < -160 { sd.setLevel(.full) }
                else if dy > 90 || p > 260 { sd.close() }
            }
    }
}


// MARK: - The card

/// SunnySD.dc.html's app card: padding 0 20 48, 20 between parts.
struct SDCard: View {
    let sd: SDStore
    let privacy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// What is being typed in a count field (false calls, true puts); nil shows the count.
    @State private var typed: [Bool: String] = [:]
    @FocusState private var field: Bool?

    /// README 1.6: positions move 0.45 s on cubic-bezier(.3, 1.1, .4, 1); none with Reduce Motion.
    static let motion = Animation.timingCurve(0.3, 1.1, 0.4, 1, duration: 0.45)
    private var move: Animation? { reduce ? nil : Self.motion }

    var body: some View {
        let r = sd.reply(sd.book, sd.t)
        VStack(alignment: .leading, spacing: 20) {
            if let r, let p = SDPair(r, sd.pick) {
                let sm = sd.sale(r, p, privacy: privacy)
                VStack(alignment: .leading, spacing: 14) {
                    grabber
                    header(r, p)
                }
                VStack(alignment: .leading, spacing: 14) {
                    expiries(r, p)
                    if !p.exp.sig.isEmpty { signals(p.exp) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    howMany(p, sm)
                    strikes(r, p)
                }
                SDSalePanel(m: sm)
                Text(sm.foot).sType(SType(size: 12, weight: 400, line: 16, tracking: 0), tabular: false).foregroundStyle(SDPal.mu)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    grabber
                    waiting(r)
                }
            }
        }
        .padding(.horizontal, S.margin)
        .foregroundStyle(SDPal.ink)
        .sensoryFeedback(.selection, trigger: sd.pick)
        // A count field raises the sheet full, so the keyboard never covers it.
        .onChange(of: field) { _, f in
            if let f { typed = [f: countOf(f) == 0 ? "" : "\(countOf(f))"]; if sd.level == .half { sd.setLevel(.full) } } else { typed = [:] }
        }
    }

    private func countOf(_ put: Bool) -> Int { put ? sd.pick.puts : sd.pick.calls }
    private func setCount(_ put: Bool, _ n: Int) { withAnimation(move) { put ? sd.setCount(puts: n) : sd.setCount(calls: n) } }

    // MARK: Grabber and header

    /// The grabber: 36 x 5 at the foot of a 20 pt strip; its target reaches 44 pt down into the gap.
    private var grabber: some View {
        Button { sd.grab() } label: {
            Capsule().fill(SDPal.ring).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 20, alignment: .bottom)
                .frame(height: 44, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, -24)
        .accessibilityLabel(sd.level == .full ? "Show half the calculator" : "Show the whole calculator")
    }

    /// Ticker 28/34 800, price 22/28 600, the move 15/20 600; the X (a 30 pt circle); IV · 1 SD 13/18 muted.
    private func header(_ r: SDReply, _ p: SDPair) -> some View {
        let mv = r.move ?? (r.prev.map { $0 > 0 ? r.price / $0 - 1 : 0 } ?? 0), e = p.exp
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(r.t).sType(SType(size: 28, weight: 800, line: 34, tracking: -0.02), tabular: false)
                        .accessibilityAddTraits(.isHeader)
                    Text("$" + SDFmt.f2(r.price)).sType(SType(size: 22, weight: 600, line: 28, tracking: 0))
                    Text((mv >= 0 ? "▲\u{00A0}" : "▼\u{00A0}") + SDFmt.pc(mv)).sType(SType(size: 15, weight: 600, line: 20, tracking: 0))
                        .foregroundStyle(mv >= 0 ? SDPal.G : SDPal.RD).fixedSize()
                }
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.name ?? r.t), \(SDFmt.f2(r.price)) dollars, \(SDFmt.saidMove(mv)) today")
                Spacer(minLength: 0)
                // No pin (Nik, 11 Nov 2026): the chart no longer draws the SD lines.
                closeButton
            }
            Text("IV \(SDFmt.pc(e.iv)) · 1 SD ±\(SDFmt.pc(e.m)) · ±$\(SDFmt.f2(r.price * e.m))")
                .sType(SType(size: 13, weight: 400, line: 18, tracking: 0)).foregroundStyle(SDPal.mu)
                .accessibilityLabel("Implied volatility \(SDFmt.saidPct(e.iv)). 1 SD by \(e.label), plus or minus \(SDFmt.saidPct(e.m)), \(SDFmt.f2(r.price * e.m)) dollars")
        }
    }

    /// The X: a 30 pt circle with a 44 pt target.
    private var closeButton: some View {
        Button { sd.close() } label: {
            Path { q in q.move(to: CGPoint(x: 2.5, y: 2.5)); q.addLine(to: CGPoint(x: 9.5, y: 9.5)); q.move(to: CGPoint(x: 9.5, y: 2.5)); q.addLine(to: CGPoint(x: 2.5, y: 9.5)) }
                .stroke(SDPal.mu, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 12, height: 12)
                .frame(width: 30, height: 30).background(Circle().fill(SDPal.trk))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-7)
        .accessibilityLabel("Close the calculator")
    }

    /// No reply yet, or none to be had: the ticker and one line.
    private func waiting(_ r: SDReply?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(sd.t).sType(SType(size: 28, weight: 800, line: 34, tracking: -0.02), tabular: false)
                Spacer(minLength: 0)
                closeButton
            }
            if r != nil {
                Text("No options to price for \(sd.t) yet.").sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(SDPal.mu)
            } else if sd.hasFailed(sd.book, sd.t) {
                Text("Could not load the SD numbers for \(sd.t).").sType(SType(size: 15, weight: 500, line: 20, tracking: 0), tabular: false).foregroundStyle(SDPal.mu)
                Button { sd.load(book: sd.book, t: sd.t, maxAge: 0) } label: {
                    Text("Try again").sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(SDPal.ink)
                        .frame(height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            } else {
                ProgressView().controlSize(.regular).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
    }

    // MARK: Expiries

    /// Chips 46 tall, radius 14, two lines (date 14/18 600 with the orange 5 pt earnings dot, days 11/14 500); picked
    /// ink. A new expiry puts the strikes back to its suggestion (README 1.2) and keeps the counts.
    private func expiries(_ r: SDReply, _ p: SDPair) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(r.exps.enumerated()), id: \.element.ex) { i, e in
                    let on = i == p.ei, d = Int(e.cd.rounded())
                    Button { withAnimation(move) { sd.choose(ex: e.ex) } } label: {
                        VStack(spacing: 1) {
                            HStack(spacing: 4) {
                                Text(e.label).sType(SType(size: 14, weight: 600, line: 18, tracking: 0))
                                if e.earn == true { Circle().fill(SDPal.OR).frame(width: 5, height: 5) }
                            }
                            .foregroundStyle(on ? SDPal.cd : SDPal.ink)
                            Text(d == 0 ? "today" : SDFmt.count(d, "day")).sType(SType(size: 11, weight: 500, line: 14, tracking: 0))
                                .foregroundStyle(on ? SDPal.cdMu : SDPal.mu)
                        }
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 12)
                        .frame(minWidth: 66, minHeight: 46, maxHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? SDPal.ink : SDPal.trk))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SDFmt.words("\(e.long ?? e.label), \(d == 0 ? "today" : SDFmt.count(d, "day") + " left")" + (e.earn == true ? ", earnings before this expiry" : "")))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, S.margin)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -S.margin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Expiry")
    }

    // MARK: Signals

    /// Outlined cards 152 wide, at least 108 tall, radius 16, snapping sideways: kicker, value and tag, the sub line,
    /// then what each did, one line per effect after an arrow.
    private func signals(_ e: SDReply.Exp) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(e.sig, id: \.key) { g in signal(g) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, S.margin, for: .scrollContent)
        .padding(.horizontal, -S.margin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Signals")
    }

    private func tone(_ t: String?) -> Color {
        switch t { case "green": SDPal.G; case "red": SDPal.RD; case "or": SDPal.OR; case "mu": SDPal.mu; default: SDPal.ink }
    }
    private func fxColor(_ k: String) -> Color {
        switch k { case "c": SDPal.CL; case "p": SDPal.PT; case "x": SDPal.OR; case "n": SDPal.mu; default: SDPal.ink }
    }

    private func signal(_ g: SDReply.Sig) -> some View {
        let tag = g.tag ?? "", sub = g.s ?? "", fx = (g.fx ?? []).filter { $0.count >= 2 }
        return VStack(alignment: .leading, spacing: 3) {
            Text(g.k.uppercased()).sType(SType(size: 11, weight: 600, line: 14, tracking: 0.05), tabular: false).foregroundStyle(SDPal.muT)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { value(g); if !tag.isEmpty { tagText(g, tag) } }
                VStack(alignment: .leading, spacing: 0) { value(g); if !tag.isEmpty { tagText(g, tag) } }
            }
            if !sub.isEmpty {
                Text(sub).sType(SType(size: 12, weight: 400, line: 16, tracking: 0)).foregroundStyle(SDPal.muT)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !fx.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(fx.enumerated()), id: \.offset) { _, x in
                        Text("→ " + x[1]).sType(SType(size: 12, weight: 600, line: 16, tracking: 0), tabular: false).foregroundStyle(fxColor(x[0]))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, 12).padding(.horizontal, 12).padding(.bottom, 10)
        .frame(width: 152, alignment: .leading)
        .frame(minHeight: 108, maxHeight: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(SDPal.ring, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SDFmt.words(([g.k, g.v, tag, sub].filter { !$0.isEmpty }.joined(separator: " · ")
                                                            + (fx.isEmpty ? "" : ". " + fx.map { $0[1] }.joined(separator: ". ")))))
    }
    private func value(_ g: SDReply.Sig) -> some View {
        Text(g.v).sType(SType(size: 20, weight: 700, line: 26, tracking: 0)).foregroundStyle(tone(g.vTone)).lineLimit(1).fixedSize()
    }
    private func tagText(_ g: SDReply.Sig, _ tag: String) -> some View {
        Text(tag).sType(SType(size: 12, weight: 600, line: 16, tracking: 0)).foregroundStyle(g.tagTone == "or" ? SDPal.OR : SDPal.mu).lineLimit(1).fixedSize()
    }

    // MARK: How many (README 1.4)

    /// Sell call on the left, Sell put under it on the right (the design's wrap at phone width): the kicker with its
    /// dot, the number (52 x 32, 17/22 700, a 1 pt ring) and the system stepper, the hint under them (12/16).
    private func howMany(_ p: SDPair, _ sm: SDSaleModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            countRow(put: false, hint: sm.callHint, over: sm.callHintOver)
            countRow(put: true, hint: sm.putHint, over: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How many")
    }

    private func countRow(put: Bool, hint: String, over: Bool) -> some View {
        let n = countOf(put), name = put ? "Puts to sell" : "Calls to sell"
        return VStack(alignment: put ? .trailing : .leading, spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(SDPal.side(put)).frame(width: 8, height: 8)
                    Text(put ? "SELL PUT" : "SELL CALL").sType(SType(size: 11, weight: 600, line: 14, tracking: 0.05), tabular: false).foregroundStyle(SDPal.muT)
                }
                .fixedSize()
                .accessibilityHidden(true)
                TextField("0", text: Binding(get: { typed[put] ?? "\(n)" }, set: { t in
                    let d = String(t.filter { $0.isASCII && $0.isNumber }.prefix(3))
                    typed[put] = d
                    setCount(put, Int(d) ?? 0)
                }))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($field, equals: put)
                .sType(SType(size: 17, weight: 700, line: 22, tracking: 0))
                .padding(.horizontal, 10)
                .frame(width: 52, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(field == put ? SDPal.ink : SDPal.ring, lineWidth: 1))
                .accessibilityLabel(name)
                // The system stepper (Liquid Glass on iOS 26).
                Stepper(name, value: Binding(get: { n }, set: { field = nil; setCount(put, $0) }), in: 0...999)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityValue("\(n)")
            }
            .frame(minHeight: 32)
            Text(hint).sType(SType(size: 12, weight: 400, line: 16, tracking: 0), tabular: false)
                .foregroundStyle(over ? SDPal.OR : SDPal.mu)
                .multilineTextAlignment(put ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toolbar {
            if field == put {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { field = nil }
                }
            }
        }
    }

    // MARK: Strikes (README 1.5)

    /// One sideways strip: the call tiles (cfg.cLo to cfg.cHi), a 1 pt rule, then the put tiles (cfg.pLo to cfg.pHi,
    /// ATM to 1 SD per D2), a tile per 0.25 SD, each group under its range (11/14 500 muted).
    private func strikes(_ r: SDReply, _ p: SDPair) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                strikeGroup(r, p, put: false)
                strikeGroup(r, p, put: true)
                    .padding(.leading, 16)
                    .overlay(alignment: .leading) { Rectangle().fill(SDPal.rule).frame(width: 1) }
            }
            .padding(.horizontal, S.margin)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -S.margin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Strikes")
    }

    private func strikeGroup(_ r: SDReply, _ p: SDPair, put: Bool) -> some View {
        let lo = put ? r.cfg.pLo : r.cfg.cLo, hi = put ? r.cfg.pHi : r.cfg.cHi, e = p.exp
        let sugK = put ? e.sug.kp : e.sug.kc, sel = put ? p.kp : p.kc, est = e.hist?.est == true
        // One strike in the money (k below 0) is a tile only on an expiry that suggests it (Nik 11 Nov).
        let ks = stride(from: lo, through: hi + 1e-9, by: 0.25).map { ($0 * 4).rounded() / 4 }.filter { $0 >= 0 || abs($0 - sugK) < 1e-6 }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(SDPal.side(put)).frame(width: 6, height: 6)
                Text(SDFmt.range(lo, hi)).sType(SType(size: 11, weight: 500, line: 14, tracking: 0)).foregroundStyle(SDPal.mu)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(put ? "Puts" : "Calls"), \(lo < 0 ? "one strike in the money" : lo == 0 ? "at the money" : SDFmt.sdNum(lo)) to \(SDFmt.sdNum(hi)) SD")
            .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                ForEach(ks, id: \.self) { k in
                    let sug = abs(k - sugK) < 1e-6, on = abs(k - sel) < 1e-6, row = SDPair.row(e, k, put: put)
                    tile(k: k, row: row, sug: sug, on: on, put: put, est: est) {
                        withAnimation(move) { put ? sd.choose(put: k) : sd.choose(call: k) }
                    }
                }
            }
        }
    }

    /// A tile 88 wide, radius 14: SD 11/14 600 with the 7 pt suggestion dot, strike 22/28 700, premium and won 12/16.
    private func tile(k: Double, row: SDReply.Row, sug: Bool, on: Bool, put: Bool, est: Bool, go: @escaping () -> Void) -> some View {
        let mc = on ? SDPal.cdMu : SDPal.muT
        let won = row.won.map { (est ? "≈ " : "") + SDFmt.pc($0) + " won" }
        return Button(action: go) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(SDFmt.sdl(k)).sType(SType(size: 11, weight: 600, line: 14, tracking: 0)).foregroundStyle(mc)
                    Spacer(minLength: 0)
                    if sug { Circle().fill(SDPal.side(put)).frame(width: 7, height: 7) }
                }
                Text(SDFmt.fk(row.K)).sType(SType(size: 22, weight: 700, line: 28, tracking: 0)).foregroundStyle(on ? SDPal.cd : SDPal.ink)
                Text("$" + SDFmt.f2(row.pr)).sType(SType(size: 12, weight: 400, line: 16, tracking: 0)).foregroundStyle(mc)
                Text(won ?? " ").sType(SType(size: 12, weight: 400, line: 16, tracking: 0)).foregroundStyle(mc).minimumScaleFactor(0.8)
            }
            .lineLimit(1)
            .padding(.vertical, 10).padding(.horizontal, 12)
            .frame(width: 88, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? SDPal.ink : SDPal.tile))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(put ? "Put" : "Call") at \(SDFmt.saidSD(k)), strike \(SDFmt.fk(row.K)), \(SDFmt.f2(row.pr)) dollars a share"
                            + (row.won.map { ", \(est ? "about " : "")\(SDFmt.saidPct($0)) won in 5 years" } ?? "")
                            + (sug ? ", suggested" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - What the sale does (README 1.6 to 1.8)

/// A panel with a 1 pt ring (padding 18, radius 20): the sentence, the title and the key, the three lanes, the Calls
/// and Puts cards, and the note on legs left out. Draws SDSaleModel only.
private struct SDSalePanel: View {
    let m: SDSaleModel
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sentence
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(m.title.uppercased()).sType(SType(size: 11, weight: 600, line: 14, tracking: 0.05), tabular: false).foregroundStyle(SDPal.muT)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    SXFlowGaps(column: 12, row: 6) {
                        key("Profit") { RoundedRectangle(cornerRadius: 4).fill(SDPal.zG) }
                        key("Loss") { RoundedRectangle(cornerRadius: 4).fill(SDPal.zR) }
                        if m.both {
                            key("Changed by the sale") {
                                RoundedRectangle(cornerRadius: 4).fill(SDPal.mu).overlay(SDStripes(step: 7, width: 3).fill(Color.black.opacity(0.4))).clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        key("Held") { RoundedRectangle(cornerRadius: 4).fill(SDPal.cd).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(SDPal.muT, lineWidth: 1.5)) }
                        key("New") { RoundedRectangle(cornerRadius: 4).fill(SDPal.ink) }
                    }
                    .accessibilityHidden(true)
                }
                lanes
            }
            if !m.cards.isEmpty {
                VStack(alignment: .leading, spacing: 10) { ForEach(m.cards) { SDSideCard(c: $0) } }
            }
            if let g = m.gone {
                Text(g).sType(SType(size: 12, weight: 400, line: 16, tracking: 0), tabular: false).foregroundStyle(SDPal.mu)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(SDPal.panelRing, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What the sale does")
    }

    /// 15/22, each run its own weight and colour.
    private var sentence: some View {
        var a = AttributedString()
        for s in m.head {
            var r = AttributedString(s.t)
            r.font = SType(size: 15, weight: s.w, line: 22, tracking: 0).font(tabular: true)
            r.foregroundColor = SDSalePanel.color(s.tone)
            a += r
        }
        let t = SType(size: 15, weight: 400, line: 22, tracking: 0)
        return Text(a).lineSpacing(t.lineSpacing).padding(.vertical, max(0, t.line - t.uiFont().lineHeight) / 2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(SDFmt.words(m.head.map(\.t).joined()))
    }

    static func color(_ t: SDSaleModel.Tone) -> Color {
        switch t { case .ink: SDPal.ink; case .mu: SDPal.mu; case .muT: SDPal.muT; case .green: SDPal.gT; case .red: SDPal.rT; case .orange: SDPal.OR }
    }

    private func key<M: View>(_ t: String, @ViewBuilder mark: () -> M) -> some View {
        HStack(spacing: 6) {
            mark().frame(width: 16, height: 8)
            Text(t).sType(SType(size: 12, weight: 400, line: 16, tracking: 0), tabular: false).foregroundStyle(SDPal.muT)
        }
    }

    /// "$38.31 today" over the lanes, then Held, + New and = Both.
    private var lanes: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { g in
                Text(m.todayT).sType(SType(size: 11, weight: 600, line: 14, tracking: 0)).foregroundStyle(SDPal.muT)
                    .fixedSize()
                    .position(x: g.size.width * max(0.1, min(0.9, m.todayX / 100)), y: 7)
            }
            .frame(height: 18)
            .accessibilityHidden(true)
            ForEach(Array(m.lanes.enumerated()), id: \.element.id) { i, ln in
                SDLaneView(ln: ln, todayX: m.todayX)
                    .padding(.top, i == 0 ? 0 : i == 1 ? 12 : 14)
                    .padding(.bottom, i == 0 ? 12 : i == 1 ? 14 : 0)
                    .overlay(alignment: .top) { if i == 2 { Rectangle().fill(SDPal.rule).frame(height: 1) } }
            }
        }
        .animation(reduce ? nil : SDCard.motion, value: m.lanes.map(\.said))
    }
}

/// A chip: Held outlined, New filled ink, Both grey (20 tall, 11/14 700 uppercase; small: 16 tall, 10/12).
private struct SDChip: View {
    let t: String
    let kind: Character
    var small = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: small ? 8 : 10, style: .continuous)
        Text(t.uppercased())
            .sType(small ? SType(size: 10, weight: 700, line: 12, tracking: 0.04) : SType(size: 11, weight: 700, line: 14, tracking: 0.04), tabular: false)
            .foregroundStyle(kind == "n" ? SDPal.cd : SDPal.ink)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, small ? 6 : 8)
            .frame(height: small ? 16 : 20)
            .background(shape.fill(kind == "n" ? SDPal.ink : kind == "b" ? SDPal.nB : SDPal.cd))
            .overlay { if kind == "h" { shape.strokeBorder(SDPal.muT, lineWidth: 1.5) } }
    }
}

/// Diagonal stripes at 135°: `width` on, the rest of `step` off (the design's repeating-linear-gradient).
private struct SDStripes: Shape {
    let step: CGFloat
    let width: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX - r.height
        while x < r.maxX {
            p.move(to: CGPoint(x: x, y: r.maxY)); p.addLine(to: CGPoint(x: x + width, y: r.maxY))
            p.addLine(to: CGPoint(x: x + width + r.height, y: r.minY)); p.addLine(to: CGPoint(x: x + r.height, y: r.minY)); p.closeSubpath()
            x += step
        }
        return p
    }
}

/// One lane: its label row (the sign, the chip, the chance of profit 20 pt, 24 pt green in Both, the line after it,
/// Both's change against Held), then the bar area: today's dashed line, the bar (green profit, red loss, stripes
/// where Both's sign differs from Held's), the strikes above it, the breakevens under it (and Held's above Both's),
/// and the white-ringed dot at today on Both. Every mark sits by .position in a fixed box.
private struct SDLaneView: View {
    let ln: SDSaleModel.Lane
    let todayX: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label
            GeometryReader { g in
                let W = g.size.width, X = { (p: Double) in CGFloat(p / 100) * W }
                ZStack(alignment: .topLeading) {
                    Path { q in q.move(to: CGPoint(x: X(todayX), y: 0)); q.addLine(to: CGPoint(x: X(todayX), y: ln.H)) }
                        .stroke(SDPal.ring, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    bar(W).frame(width: W, height: ln.thk).position(x: W / 2, y: ln.bt + ln.thk / 2)
                    ForEach(ln.pills) { p in
                        let c = SDPal.side(p.put)
                        Path { q in q.move(to: CGPoint(x: X(p.x), y: p.stemTop)); q.addLine(to: CGPoint(x: X(p.x), y: p.stemTop + p.stemH)) }
                            .stroke(c, style: StrokeStyle(lineWidth: 2, dash: p.new ? [] : [4, 3]))
                        Text(p.label).sType(SType(size: 11, weight: 700, line: 14, tracking: 0))
                            .foregroundStyle(p.new ? (scheme == .dark ? Color.black : Color.white) : c)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 7).frame(height: 18)
                            .background(Capsule().fill(p.new ? c : SDPal.cd))
                            .overlay { if !p.new { Capsule().strokeBorder(c, lineWidth: 1.5) } }
                            .position(x: X(p.lx), y: p.y + 9)
                    }
                    ForEach(ln.bes) { b in
                        Path { q in q.move(to: CGPoint(x: X(b.x), y: b.notchTop)); q.addLine(to: CGPoint(x: X(b.x), y: b.notchTop + b.notchH)) }
                            .stroke(b.held ? SDPal.muT : SDPal.ink, style: StrokeStyle(lineWidth: 2, dash: b.held ? [4, 3] : []))
                        beLabel(b).frame(width: 240, height: 60, alignment: .top).position(x: X(b.lx), y: b.y + 30)
                    }
                    if ln.dot {
                        Circle().fill(SDPal.ink).frame(width: 14, height: 14)
                            .background(Circle().fill(SDPal.cd).padding(-3))
                            .position(x: X(todayX), y: ln.bt + ln.thk / 2)
                    }
                }
                .frame(width: W, height: ln.H, alignment: .topLeading)
            }
            .frame(height: ln.H)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ln.said)
    }

    /// The sign (10 wide), the chip, the chance, the line after it; Both's pill under them when it does not fit.
    private var label: some View {
        let lead = HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(ln.op).sType(SType(size: 15, weight: 600, line: 20, tracking: 0), tabular: false).foregroundStyle(SDPal.muT).frame(width: 10, alignment: .leading)
            SDChip(t: ln.name, kind: ln.id == "h" ? "h" : ln.id == "n" ? "n" : "b")
        }
        let cop = ln.cop.map { c in
            Text(c).sType(SType(size: ln.id == "b" ? 24 : 20, weight: 700, line: ln.id == "b" ? 28 : 23, tracking: -0.02))
                .foregroundStyle(ln.id == "b" ? SDPal.G : SDPal.ink).fixedSize()
        }
        let sub = Text(ln.sub).sType(SType(size: 12, weight: 400, line: 16, tracking: 0), tabular: false).foregroundStyle(SDPal.mu)
        let pill = ln.ch.map { t in
            Text(t).sType(SType(size: 12, weight: 600, line: 16, tracking: 0))
                .foregroundStyle(ln.chK > 0 ? SDPal.gT : ln.chK < 0 ? SDPal.rT : SDPal.muT)
                .padding(.vertical, 3).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ln.chK > 0 ? SDPal.gB : ln.chK < 0 ? SDPal.rB : SDPal.nB))
                .fixedSize()
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) { lead; cop; sub.fixedSize(); pill }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) { lead; cop; sub.fixedSize() }
                pill
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) { lead; cop }
                sub.fixedSize(horizontal: false, vertical: true)
                pill
            }
        }
    }

    /// The bar: the track, green where the lane profits and red where it loses, stripes where Both changed it.
    private func bar(_ W: CGFloat) -> some View {
        let X = { (p: Double) in CGFloat(p / 100) * W }
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(SDPal.trk)
            ForEach(ln.zones) { z in
                Rectangle().fill(z.pos ? SDPal.zG : SDPal.zR)
                    .frame(width: max(0, X(z.b) - X(z.a)), height: ln.thk)
                    .position(x: (X(z.a) + X(z.b)) / 2, y: ln.thk / 2)
            }
            ForEach(ln.diff) { z in
                SDStripes(step: 7, width: 3).fill(Color.black.opacity(0.4))
                    .frame(width: max(0, X(z.b) - X(z.a)), height: ln.thk)
                    .clipped()
                    .position(x: (X(z.a) + X(z.b)) / 2, y: ln.thk / 2)
            }
        }
        .clipShape(Capsule())
    }

    /// A breakeven: the price (13, 15 in Both; 12 muted with a HELD chip for Held's above Both's), `↓ 4.2% · 0.85 SD`,
    /// and in Both its change against Held in green or red; on the sheet's fill, padding 0 4.
    private func beLabel(_ b: SDSaleModel.BE) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 5) {
                if b.held { SDChip(t: "Held", kind: "h", small: true) }
                Text(b.v).sType(SType(size: b.vSize, weight: 700, line: 18, tracking: 0)).foregroundStyle(b.held ? SDPal.muT : SDPal.ink)
            }
            Text(b.s).sType(SType(size: 11, weight: 400, line: 14, tracking: 0)).foregroundStyle(SDPal.mu)
            if let ch = b.ch {
                Text(ch).sType(SType(size: 11, weight: 700, line: 14, tracking: 0)).foregroundStyle(b.chK > 0 ? SDPal.gT : SDPal.rT)
            }
        }
        .lineLimit(1).fixedSize()
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(SDPal.cd))
    }
}

/// The Calls or Puts card (1.7): Held | New, each leg and that side's breakeven, then = Both · breakeven with its
/// change against Held (or New alone). Padding 16, radius 18, on the cards' fill.
private struct SDSideCard: View {
    let c: SDSaleModel.Card
    var body: some View {
        let col = SDPal.side(c.put)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(col).frame(width: 8, height: 8)
                Text(c.title.uppercased()).sType(SType(size: 11, weight: 600, line: 14, tracking: 0.05), tabular: false).foregroundStyle(SDPal.muT)
            }
            HStack(alignment: .top, spacing: 0) {
                column(c.cols[0], col).padding(.trailing, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                column(c.cols[1], col).padding(.leading, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay(alignment: .leading) { Rectangle().fill(SDPal.rule).frame(width: 1) }
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("=").sType(SType(size: 15, weight: 600, line: 14, tracking: 0), tabular: false).foregroundStyle(SDPal.muT)
                    Text("BOTH · BREAKEVEN").sType(SType(size: 11, weight: 700, line: 14, tracking: 0.04), tabular: false).foregroundStyle(SDPal.ink)
                }
                let from = HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let f = c.from {
                        Text(f).sType(SType(size: 15, weight: 600, line: 20, tracking: 0)).foregroundStyle(SDPal.mu)
                        Text("→").sType(SType(size: 15, weight: 400, line: 20, tracking: 0), tabular: false).foregroundStyle(SDPal.mu)
                    }
                    Text(c.bV).sType(SType(size: 26, weight: 700, line: 32, tracking: -0.02))
                }
                let s = Text(c.bS).sType(SType(size: 13, weight: 400, line: 18, tracking: 0)).foregroundStyle(SDPal.muT)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { from; s }
                    VStack(alignment: .leading, spacing: 2) { from; s }
                }
                if let ch = c.ch {
                    Text(ch).sType(SType(size: 13, weight: 600, line: 18, tracking: 0))
                        .foregroundStyle(c.chK > 0 ? SDPal.gT : c.chK < 0 ? SDPal.rT : SDPal.muT)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4).padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(c.chK > 0 ? SDPal.gB : c.chK < 0 ? SDPal.rB : SDPal.nB))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(SDPal.rule).frame(height: 1) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SDPal.cardBg))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.said)
    }

    private func column(_ k: SDSaleModel.Col, _ col: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SDChip(t: k.held ? "Held" : "New", kind: k.held ? "h" : "n")
            ForEach(k.legs) { l in
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.K).sType(SType(size: 17, weight: 700, line: 22, tracking: 0)).foregroundStyle(col)
                    Text(l.pr).sType(SType(size: 12, weight: 400, line: 16, tracking: 0)).foregroundStyle(SDPal.muT)
                    Text(l.mv).sType(SType(size: 12, weight: 400, line: 16, tracking: 0)).foregroundStyle(SDPal.mu)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if k.legs.isEmpty {
                Text(k.empty).sType(SType(size: 13, weight: 400, line: 18, tracking: 0), tabular: false).foregroundStyle(SDPal.mu)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let be = k.be {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Breakeven").sType(SType(size: 11, weight: 600, line: 14, tracking: 0), tabular: false).foregroundStyle(SDPal.mu)
                    Text(be).sType(SType(size: 17, weight: 700, line: 22, tracking: 0))
                    Text(k.beS).sType(SType(size: 11, weight: 400, line: 14, tracking: 0)).foregroundStyle(SDPal.mu)
                }
            }
        }
    }
}
