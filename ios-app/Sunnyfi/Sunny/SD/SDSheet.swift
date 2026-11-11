//
//  SDSheet.swift
//  Sunny
//
//  The SD calculator sheet (handoff 11 Nov 2026, README 1.1 and 1.3, SunnySD.dc.html app card, Explorations 137a).
//  The SD chip on Positions raises it to half (600 pt showing); the grabber, or a swipe up, takes it full (56 pt from
//  the top, the page dimmed behind, the sheet scrolls); the grabber, a swipe down or a pull past the top takes it back
//  to half. X, a tap on the dim, or a swipe down from half closes it. It lies over the tab bar, as the design's does.
//
//  Top to bottom, as the card: header (ticker, price, today's move, IV · 1 SD, the pin and X), the expiries, the
//  signals (outlined, snap sideways), Sell call and Sell put tiles (the dot is the suggestion, ink is what is picked),
//  Chance of profit with the total and the timeline, and Every SD with the Calls | Puts switch.
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
        // At half the sheet holds still (a swipe moves the sheet); full, it scrolls.
        .scrollDisabled(!full)
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

/// SunnySD.dc.html's app card: padding 0 20 48, 18 between parts.
struct SDCard: View {
    let sd: SDStore
    let privacy: Bool

    var body: some View {
        let r = sd.reply(sd.book, sd.t)
        VStack(alignment: .leading, spacing: 18) {
            grabber
            if let r, let p = SDPair(r, sd.pick) {
                header(r, p)
                expiries(r, p)
                if !p.exp.sig.isEmpty { signals(p.exp) }
                strikes(r, p)
                both(r, p)
                every(r, p)
            } else {
                waiting(r)
            }
        }
        .padding(.horizontal, S.margin)
        .foregroundStyle(SDPal.ink)
        .sensoryFeedback(.selection, trigger: sd.pick)
        .sensoryFeedback(.selection, trigger: sd.side)
    }

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

    /// Ticker 28/34 800, price 22/28 600, the move 15/20 600; the pin and X (30 pt circles); IV · 1 SD 13/18 muted.
    private func header(_ r: SDReply, _ p: SDPair) -> some View {
        let mv = r.move ?? (r.prev.map { $0 > 0 ? r.price / $0 - 1 : 0 } ?? 0), e = p.exp
        let pinned = sd.isPinned(sd.book, sd.t)
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
                HStack(spacing: 8) {
                    circle(bg: pinned ? SDPal.ink : SDPal.trk) {
                        SDPinGlyph().stroke(pinned ? SDPal.cd : SDPal.ink, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                            .frame(width: 12, height: 12)
                    } action: { withAnimation(S.fade) { sd.togglePin() } }
                    .accessibilityLabel("Pin to the chart")
                    .accessibilityValue(pinned ? "On" : "Off")
                    .accessibilityHint("Keeps the SD band and both strikes on the chart after the calculator closes")
                    .accessibilityAddTraits(.isToggle)
                    .sensoryFeedback(.selection, trigger: pinned)
                    circle(bg: SDPal.trk) {
                        Path { q in q.move(to: CGPoint(x: 2.5, y: 2.5)); q.addLine(to: CGPoint(x: 9.5, y: 9.5)); q.move(to: CGPoint(x: 9.5, y: 2.5)); q.addLine(to: CGPoint(x: 2.5, y: 9.5)) }
                            .stroke(SDPal.mu, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                            .frame(width: 12, height: 12)
                    } action: { sd.close() }
                    .accessibilityLabel("Close the calculator")
                }
            }
            Text("IV \(SDFmt.pc(e.iv)) · 1 SD ±\(SDFmt.pc(e.m)) · ±$\(SDFmt.f2(r.price * e.m))")
                .sType(SType(size: 13, weight: 400, line: 18, tracking: 0)).foregroundStyle(SDPal.mu)
                .accessibilityLabel("Implied volatility \(SDFmt.saidPct(e.iv)). 1 SD by \(e.label), plus or minus \(SDFmt.saidPct(e.m)), \(SDFmt.f2(r.price * e.m)) dollars")
        }
    }

    /// A 30 pt circle with a 44 pt target.
    private func circle<G: View>(bg: Color, @ViewBuilder glyph: () -> G, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            glyph().frame(width: 30, height: 30).background(Circle().fill(bg))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-7)
    }

    /// No reply yet, or none to be had: the ticker and one line.
    private func waiting(_ r: SDReply?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(sd.t).sType(SType(size: 28, weight: 800, line: 34, tracking: -0.02), tabular: false)
                Spacer(minLength: 0)
                circle(bg: SDPal.trk) {
                    Path { q in q.move(to: CGPoint(x: 2.5, y: 2.5)); q.addLine(to: CGPoint(x: 9.5, y: 9.5)); q.move(to: CGPoint(x: 9.5, y: 2.5)); q.addLine(to: CGPoint(x: 2.5, y: 9.5)) }
                        .stroke(SDPal.mu, style: StrokeStyle(lineWidth: 1.8, lineCap: .round)).frame(width: 12, height: 12)
                } action: { sd.close() }
                .accessibilityLabel("Close the calculator")
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

    /// Chips 46 tall, radius 14, two lines (date 14/18 600 with the orange 5 pt earnings dot, days 11/14 500); picked ink.
    private func expiries(_ r: SDReply, _ p: SDPair) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(r.exps.enumerated()), id: \.element.ex) { i, e in
                    let on = i == p.ei, d = Int(e.cd.rounded())
                    Button { withAnimation(S.fade) { sd.choose(ex: e.ex) } } label: {
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
        .scrollDisabled(false)
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
        .scrollDisabled(false)
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

    // MARK: Strikes

    /// Sell call (cfg.cLo to cfg.cHi) and Sell put (cfg.pLo to cfg.pHi, ATM to 1 SD per D2), a tile per 0.25 SD.
    private func strikes(_ r: SDReply, _ p: SDPair) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            strikeRow(r, p, put: false)
            strikeRow(r, p, put: true)
        }
    }

    private func strikeRow(_ r: SDReply, _ p: SDPair, put: Bool) -> some View {
        let lo = put ? r.cfg.pLo : r.cfg.cLo, hi = put ? r.cfg.pHi : r.cfg.cHi, e = p.exp
        let ks = stride(from: lo, through: hi + 1e-9, by: 0.25).map { ($0 * 4).rounded() / 4 }
        let sugK = put ? e.sug.kp : e.sug.kc, sel = put ? p.kp : p.kc, est = e.hist?.est == true
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(SDPal.side(put)).frame(width: 8, height: 8)
                Text(put ? "Sell put" : "Sell call").sType(SType(size: 13, weight: 600, line: 16, tracking: 0), tabular: false)
                Text(SDFmt.range(lo, hi)).sType(SType(size: 13, weight: 500, line: 16, tracking: 0)).foregroundStyle(SDPal.mu)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(put ? "Sell put" : "Sell call"), \(lo == 0 ? "at the money" : SDFmt.sdNum(lo)) to \(SDFmt.sdNum(hi)) SD")
            .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ks, id: \.self) { k in
                        let sug = abs(k - sugK) < 1e-6, on = abs(k - sel) < 1e-6, row = SDPair.row(e, k, put: put)
                        tile(k: k, row: row, sug: sug, on: on, put: put, est: est) {
                            withAnimation(S.fade) { put ? sd.choose(put: k) : sd.choose(call: k) }
                        }
                    }
                }
                .padding(.horizontal, S.margin)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(false)
            .padding(.horizontal, -S.margin)
        }
    }

    /// A tile 94 wide, radius 14: SD 11/14 600 with the 7 pt suggestion dot, strike 22/28 700, premium and won 12/16.
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
            .frame(width: 94, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? SDPal.ink : SDPal.tile))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(put ? "Put" : "Call") at \(SDFmt.saidSD(k)), strike \(SDFmt.fk(row.K)), \(SDFmt.f2(row.pr)) dollars a share"
                            + (row.won.map { ", \(est ? "about " : "")\(SDFmt.saidPct($0)) won in 5 years" } ?? "")
                            + (sug ? ", suggested" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Chance of profit and the timeline

    /// On the tile fill, padding 14 16 12, radius 18: the kicker and the chance (30/36 800 green) on the left, the total
    /// (17/22 700) and counts on the right; the timeline under them.
    private func both(_ r: SDReply, _ p: SDPair) -> some View {
        let n = r.counts, total = (p.call.pr * Double(n.calls) + p.put.pr * Double(n.puts)) * 100
        let totT = BriefWords.plain(SDFmt.money(total), privacy: privacy)
        let sub = "\(SDFmt.count(n.calls, "call")) and \(SDFmt.count(n.puts, "put")) · $\(SDFmt.f2(p.tot)) a share"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CHANCE OF PROFIT").sType(SType(size: 11, weight: 600, line: 14, tracking: 0.05), tabular: false).foregroundStyle(SDPal.muT)
                    Text(SDFmt.pc(p.cop)).sType(SType(size: 30, weight: 800, line: 36, tracking: -0.02)).foregroundStyle(SDPal.G)
                        .contentTransition(.numericText()).animation(S.fade, value: p.cop)
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chance of profit, \(SDFmt.saidPct(p.cop))")
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(totT).sType(SType(size: 17, weight: 700, line: 22, tracking: 0))
                    Text(sub).sType(SType(size: 12, weight: 400, line: 16, tracking: 0)).foregroundStyle(SDPal.muT)
                        .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(privacy ? "Total hidden" : BriefWords.speech(totT)) for \(SDFmt.count(n.calls, "call")) and \(SDFmt.count(n.puts, "put")), \(SDFmt.f2(p.tot)) dollars a share")
            }
            SDTimeline(S0: r.price, call: p.call, put: p.put, up: p.up, dn: p.dn)
        }
        .padding(.top, 14).padding(.horizontal, 16).padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SDPal.tile))
    }

    // MARK: Every SD

    /// "Every SD" 17/22 700 and the Calls | Puts switch; the rows 0 to 2.0 SD for that side, the allowed range boxed.
    private func every(_ r: SDReply, _ p: SDPair) -> some View {
        let put = sd.side == .puts, e = p.exp
        let lo = put ? r.cfg.pLo : r.cfg.cLo, hi = put ? r.cfg.pHi : r.cfg.cHi
        let rows = put ? e.rows.p : e.rows.c
        let inZ = { (k: Double) in k >= lo - 1e-9 && k <= hi + 1e-9 }
        let pre = rows.filter { $0.k < lo - 1e-9 }, zone = rows.filter { inZ($0.k) }, post = rows.filter { $0.k > hi + 1e-9 }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("Every SD").sType(SType(size: 17, weight: 700, line: 22, tracking: 0), tabular: false).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                SDSideSwitch(side: Binding(get: { sd.side }, set: { sd.side = $0 }))
            }
            VStack(spacing: 0) {
                SDTableHead()
                ForEach(pre, id: \.k) { row in tableRow(row, e, p, put: put, zone: nil) }
                VStack(spacing: 0) {
                    ForEach(Array(zone.enumerated()), id: \.element.k) { i, row in
                        tableRow(row, e, p, put: put, zone: (first: i == 0, last: i == zone.count - 1))
                    }
                }
                .overlay { if !zone.isEmpty { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(put ? SDPal.pzL : SDPal.czL, lineWidth: 1) } }
                ForEach(post, id: \.k) { row in tableRow(row, e, p, put: put, zone: nil) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Strikes by SD, \(put ? "puts" : "calls")")
        }
    }

    /// One row: min 42 tall, padding 0 8, 13/16 (700 when picked). In the range: the side's light tint; picked: the
    /// stronger tint and a 1.5 pt ring. The suggestion: a 6 pt dot after the SD; its moved strike after an arrow.
    private func tableRow(_ row: SDReply.Row, _ e: SDReply.Exp, _ p: SDPair, put: Bool, zone: (first: Bool, last: Bool)?) -> some View {
        let sugK = put ? e.sug.kp : e.sug.kc, sel = put ? p.kp : p.kc
        let sug = abs(row.k - sugK) < 1e-6, on = abs(row.k - sel) < 1e-6
        let moved = put ? e.sug.put.K : e.sug.call.K
        let K = SDFmt.fk(row.K) + (sug && abs(moved - row.K) > 1e-9 ? " → " + SDFmt.fk(moved) : "")
        let pr = (row.est ? "≈ " : "") + SDFmt.f2(row.pr) + (row.liq && !row.est ? " !" : "")
        let r: CGFloat = 10
        let shape = UnevenRoundedRectangle(topLeadingRadius: zone == nil || zone!.first ? r : 0, bottomLeadingRadius: zone == nil || zone!.last ? r : 0,
                                           bottomTrailingRadius: zone == nil || zone!.last ? r : 0, topTrailingRadius: zone == nil || zone!.first ? r : 0,
                                           style: .continuous)
        let tint: Color = zone == nil ? .clear : on ? (put ? SDPal.pzB2 : SDPal.czB2) : (put ? SDPal.pzB : SDPal.czB)
        return HStack(alignment: .center, spacing: 4) {
            HStack(spacing: 4) {
                Text(SDFmt.sdNum(row.k))
                if sug { Circle().fill(SDPal.side(put)).frame(width: 6, height: 6) }
            }
            .frame(width: 40, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(K)
                Text(SDFmt.dir(row.pct)).sType(SType(size: 10, weight: 500, line: 12, tracking: 0)).foregroundStyle(SDPal.mu)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Text(pr).frame(maxWidth: .infinity, alignment: .trailing)
            Text(SDFmt.f2(row.be)).frame(maxWidth: .infinity, alignment: .trailing)
            Text(SDFmt.pc(row.itm)).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .sType(SType(size: 13, weight: on ? 700 : 500, line: 16, tracking: 0))
        .lineLimit(1).minimumScaleFactor(0.8)
        .padding(.horizontal, 8)
        .frame(minHeight: 42)
        .background(shape.fill(tint))
        .overlay { if on { shape.strokeBorder(SDPal.side(put), lineWidth: 1.5) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(SDFmt.saidSD(row.k))\(sug ? ", suggested" : "")\(on ? ", picked" : ""), strike \(SDFmt.fk(row.K))"
                            + (sug && abs(moved - row.K) > 1e-9 ? " moved to \(SDFmt.fk(moved))" : "")
                            + ", \(SDFmt.saidMove(row.pct)), premium \(SDFmt.f2(row.pr))\(row.est ? ", estimated" : "")\(row.liq && !row.est ? ", thin market" : "")"
                            + ", breakeven \(SDFmt.f2(row.be)), \(SDFmt.saidPct(row.itm)) chance in the money"
                            + (zone == nil ? "" : ", in the allowed range"))
    }
}

/// The table's head: SD (40 wide), Strike, Premium, Breakeven, In the money; 11/13 600 muted, padding 0 8 4.
private struct SDTableHead: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Text("SD").frame(width: 40, alignment: .leading)
            Text("Strike").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Premium").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Breakeven").frame(maxWidth: .infinity, alignment: .trailing)
            Text("In the money").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .sType(SType(size: 11, weight: 600, line: 13, tracking: 0), tabular: false)
        .foregroundStyle(SDPal.mu)
        .lineLimit(1).minimumScaleFactor(0.8)
        .padding(.horizontal, 8).padding(.bottom, 4)
        .accessibilityHidden(true)
    }
}

/// The glass Calls | Puts switch: a track (padding 2, fully round), a 76 x 28 thumb that springs across, 13/16 labels
/// (600 on, 500 off). Each half is a 44 pt target.
private struct SDSideSwitch: View {
    @Binding var side: SDStore.Side
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        let dark = scheme == .dark, put = side == .puts
        ZStack(alignment: .leading) {
            Capsule().fill(SDPal.trk).frame(width: 156, height: 32)
            Capsule().fill(SDPal.segOn)
                .overlay { if dark { Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5) } }
                .overlay(alignment: .top) { if dark { Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1).mask(alignment: .top) { Rectangle().frame(height: 1.5) } } }
                .overlay { if !dark { Capsule().stroke(Color.black.opacity(0.06), lineWidth: 0.5) } }
                .shadow(color: .black.opacity(dark ? 0.35 : 0.08), radius: dark ? 4 : 1, y: dark ? 2 : 1)
                .frame(width: 76, height: 28)
                .offset(x: 2 + (put ? 76 : 0))
                .animation(S.moving(S.spring, reduce), value: side)
            HStack(spacing: 0) {
                ForEach([SDStore.Side.calls, .puts], id: \.self) { s in
                    Button { side = s } label: {
                        Text(s == .calls ? "Calls" : "Puts")
                            .sType(SType(size: 13, weight: side == s ? 600 : 500, line: 16, tracking: 0), tabular: false)
                            .foregroundStyle(SDPal.ink)
                            .frame(width: 76, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(side == s ? .isSelected : [])
                }
            }
            .padding(.leading, 2)
        }
        .frame(width: 156, height: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Side")
    }
}

/// The profit zone, 94 tall (card136 pz): the put and call at their prices on top with a tick down to the bar, the
/// distance from today to each (side colours at 55%), the bar (track, light green breakeven to breakeven, stronger
/// green strike to strike), today's dot, then the lower breakeven, today and the upper breakeven. Scaled from the lower
/// breakeven (or the put) to the upper (or the call), 12% padding each side.
private struct SDTimeline: View {
    let S0: Double
    let call: SDReply.Row
    let put: SDReply.Row
    let up: Double
    let dn: Double
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let a0 = min(dn, put.K), b0 = max(up, call.K), pad = (b0 - a0) * 0.12, A = a0 - pad, B = max(b0 + pad, A + 1e-6)
            let X = { (v: Double) -> CGFloat in CGFloat((v - A) / (B - A)) * w }
            ZStack(alignment: .topLeading) {
                Capsule().fill(SDPal.trk).frame(width: w, height: 6).offset(y: 46)
                Capsule().fill(SDPal.gz).frame(width: max(0, X(up) - X(dn)), height: 6).offset(x: X(dn), y: 46)
                Rectangle().fill(SDPal.gz2).frame(width: max(0, X(call.K) - X(put.K)), height: 6).offset(x: X(put.K), y: 46)
                ForEach([false, true], id: \.self) { isCall in
                    let K = isCall ? call.K : put.K, c = SDPal.side(!isCall)
                    Capsule().fill(c).opacity(0.55).frame(width: abs(X(K) - X(S0)), height: 2).offset(x: min(X(K), X(S0)), y: 36)
                    label(SDFmt.dir(K / S0 - 1), 11, 700, c).position(x: (X(K) + X(S0)) / 2, y: 18 + 7)
                    VStack(spacing: 2) {
                        label((isCall ? "Call " : "Put ") + SDFmt.fk(K), 11, 700, c)
                        RoundedRectangle(cornerRadius: 1).fill(c).frame(width: 2, height: 30)
                    }
                    .fixedSize()
                    .position(x: X(K), y: 23)
                }
                Circle().fill(SDPal.ink).frame(width: 12, height: 12)
                    .background(Circle().fill(SDPal.dot).padding(-3))
                    .position(x: X(S0), y: 49)
                foot(SDFmt.f2(dn), "breakeven").position(x: X(dn), y: 60 + 13.5)
                foot("$" + SDFmt.f2(S0), "today").position(x: X(S0), y: 60 + 13.5)
                foot(SDFmt.f2(up), "breakeven").position(x: X(up), y: 60 + 13.5)
            }
        }
        .frame(height: 94)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Profit zone")
        .accessibilityValue("Profit between the breakevens \(SDFmt.f2(dn)) and \(SDFmt.f2(up)). Today \(SDFmt.f2(S0)) dollars. "
                            + "Put \(SDFmt.fk(put.K)), \(SDFmt.saidMove(put.K / S0 - 1)). Call \(SDFmt.fk(call.K)), \(SDFmt.saidMove(call.K / S0 - 1)).")
    }
    private func label(_ t: String, _ size: CGFloat, _ wt: CGFloat, _ c: Color) -> some View {
        Text(t).sType(SType(size: size, weight: wt, line: 14, tracking: 0)).foregroundStyle(c).lineLimit(1).fixedSize()
    }
    private func foot(_ v: String, _ s: String) -> some View {
        VStack(spacing: 0) {
            Text(v).sType(SType(size: 11, weight: 600, line: 14, tracking: 0)).foregroundStyle(SDPal.ink)
            Text(s).sType(SType(size: 10, weight: 400, line: 13, tracking: 0), tabular: false).foregroundStyle(SDPal.muT)
        }
        .lineLimit(1).fixedSize()
    }
}
