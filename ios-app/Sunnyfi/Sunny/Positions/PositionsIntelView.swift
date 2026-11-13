//
//  PositionsIntelView.swift
//  Sunny
//
//  Intelligence for this week on the phone (handoff 2026-11-13-positions §3.9, App Explorations 154a), always open:
//  Today's alerts, the read (17/24) about what you sold, then the lanes on one price scale with today's line through
//  all of them (IV, SD, Gamma Exposure, Technicals, Move, Held), each with three boxes under it; a tap on a box opens
//  its detail in place (one at a time; tap again or ✕ to close).
//  Walls and technicals stay faint (.38) until today's session reaches them: touched = yellow with a soft glow, closed
//  through = a capsule with ↑ or ↓ and a line through the lane (the server's `day`, PE.levelState).
//  Geometry follows the design's markup; positions across are fractions of the track. No em dashes in any words here.
//

import SwiftUI

struct PosIntelView: View {
    let t: String
    let intel: PosIntel?
    let failed: Bool
    let loaded: Bool
    let privacy: Bool
    @Binding var box: String?
    let reduce: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Intelligence").sType(PT.section, tabular: false).foregroundStyle(PC.ink).accessibilityAddTraits(.isHeader)
                Text(intel.map { "\($0.sub) · read only · tap a box for more" } ?? "This week · read only").sType(PT.t(12, 16), tabular: false).foregroundStyle(PC.mu)
                    .accessibilityLabel(PosSay.words(intel.map { "\($0.sub), read only, tap a box for more" } ?? "This week"))
            }
            .padding(.horizontal, 14)
            if let m = intel {
                if !m.alerts.isEmpty { alerts(m).padding(.horizontal, 14) }
                theRead(m).padding(.horizontal, 14)
                todayAxis(m).padding(.horizontal, 14)
                PosLanes(m: m, privacy: privacy, box: $box, reduce: reduce)
            } else {
                Text(failed ? "Could not read \(t)’s option chain just now." : loaded ? "No expiries for \(t) this week." : "Reading \(t)’s option chain…")
                    .sType(PT.t(14, 20), tabular: false).foregroundStyle(PC.mu)
                    .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, intel == nil ? 16 : 0)
        .modifier(PosSoftCard(radius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// One chip per level hit today: closed through first (a capsule with ↑ or ↓), then touched (a yellow outline).
    private func alerts(_ m: PosIntel) -> some View {
        SXFlowGaps(column: 6, row: 6) {
            Text("TODAY").sType(PT.kicker, tabular: false).foregroundStyle(PC.mu).frame(height: 26)
            ForEach(m.alerts) { a in
                let closed = a.state != .touch
                HStack(spacing: 5) {
                    if !closed { Circle().fill(PC.touched).frame(width: 6, height: 6) }
                    Text(a.text).sType(PT.t(12, 16, 600), tabular: false).lineLimit(1)
                }
                .foregroundStyle(closed ? PC.onInk : PC.touched)
                .padding(.horizontal, 10).frame(height: 26)
                .background { Capsule().fill(closed ? PC.ink : PC.touched.opacity(0.12)) }
                .overlay { if !closed { Capsule().strokeBorder(PC.touched.opacity(0.55), lineWidth: 1) } }
                .accessibilityLabel(PosSay.words(a.text))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Alerts today")
    }

    /// The read (§3.9.4): the lead 600 in ink, the rest 400 at .72; four lines' room held; fades in on change.
    private func theRead(_ m: PosIntel) -> some View {
        let key = m.read.lead + m.read.rest
        let kick = "The read · \(m.long) · \(m.readOn)"
        return VStack(alignment: .leading, spacing: 6) {
            Text(kick.uppercased()).sType(PT.kicker, tabular: false).foregroundStyle(PC.mu)
            ZStack(alignment: .topLeading) {
                Text("\(Text(m.read.lead).font(.inter(17, 600)).foregroundStyle(PC.ink)) \(Text(m.read.rest).font(.inter(17, 400)).foregroundStyle(PC.ink.opacity(0.72)))")
                    .sType(PT.t(17, 24), tabular: false)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(key)
                    .transition(reduce ? .identity : .opacity.combined(with: .offset(y: 3)))
            }
            .animation(reduce ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.4), value: key)
        }
        .frame(minHeight: 24 * 4 + 22, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PosSay.words("\(kick). \(m.read.lead) \(m.read.rest)"))
    }

    /// "Today $38.09" over the scale, then the price ticks.
    private func todayAxis(_ m: PosIntel) -> some View {
        GeometryReader { g in
            let tw = g.size.width, sc = m.scale
            let lab = "Today \(PE.f2(m.S))", lw = PosLanes.tx(lab, 11) + 14
            ZStack(alignment: .topLeading) {
                Text(lab).sType(PT.t(11, 14, 700)).foregroundStyle(PC.onInk).lineLimit(1).fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(PC.ink))
                    .offset(x: PosLanes.at(sc.fr(m.S), lw, tw), y: 3)
                ForEach(sc.ticks, id: \.self) { v in
                    let s = "$" + PE.num(v, 2)
                    Text(s).sType(PT.t(11, 13)).foregroundStyle(PC.mu).fixedSize()
                        .offset(x: PosLanes.at(sc.fr(v), PosLanes.tx(s, 11), tw), y: 24)
                }
            }
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }
}

// MARK: - The lanes

struct PosLanes: View {
    let m: PosIntel
    let privacy: Bool
    @Binding var box: String?
    let reduce: Bool

    /// About how wide a label is at 11 or 12 pt (the web's tx).
    static func tx(_ s: String, _ size: CGFloat = 12) -> CGFloat { CGFloat(s.count) * (size <= 11 ? 6.2 : 7) + 2 }
    /// A label's left edge: centred on f ('c'), just right of it ('r'), just left ('l'), or a share of its width left of
    /// f; always inside the track and not left of `lo`.
    static func at(_ f: Double, _ w: CGFloat, _ tw: CGFloat, _ mode: Character = "c", share: CGFloat? = nil, lo: CGFloat = 0) -> CGFloat {
        let a = CGFloat(f) * tw
        let l: CGFloat = share != nil ? a - share! * w : mode == "c" ? a - w / 2 : mode == "r" ? a + 8 : a - 8 - w
        return max(lo, min(tw - w, l))
    }

    private var sc: PE.Scale { m.scale }
    private func fr(_ x: Double) -> Double { sc.fr(x) }
    private func cl01(_ x: Double) -> Double { max(0, min(1, fr(x))) }
    private func inSc(_ x: Double?) -> Bool { x.map { fr($0) >= 0 && fr($0) <= 1 } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            lane("IV", sub: "by strike · brighter is richer", tint: PC.tintIV, key: "iv", h: 76, boxes: m.boxes.iv, empty: nil) { tw in ivTrack(tw) }
            lane("SD", sub: "priced move · 0.25 to 2", tint: PC.tintSD, key: "sd", h: 28, boxes: m.boxes.sd, empty: nil) { tw in sdTrack(tw) }
            lane("Gamma Exposure", sub: "walls · size is gamma", tint: PC.tintW, key: "w", h: 84, boxes: m.boxes.gamma,
                 empty: "No gamma walls for \(m.label) yet.") { tw in gammaTrack(tw) }
            lane("Technicals", sub: m.rsi.map { "RSI \(Int(PE.jsRound($0))) · \(PosIntel.rsiWord($0))" } ?? "averages · filled holds, hatched caps", tint: PC.tintT, key: "t", h: 84,
                 boxes: m.boxes.tech, empty: "Support, resistance and RSI come with the technicals.") { tw in techTrack(tw) }
            lane("Move", sub: "last week, this week, pace", tint: PC.tintMv, key: "mv", h: 36, boxes: m.boxes.move,
                 empty: "The week’s moves come with the closes.") { tw in moveTrack(tw) }
            lane("Held", sub: m.LH.has ? "sold for \(m.label)" : "nothing for \(m.label)", tint: PC.tintH, key: "h", h: 28, boxes: m.boxes.held,
                 empty: "Nothing sold for \(m.label).") { tw in heldTrack(tw) }
        }
    }

    // MARK: A lane: its header, its track with today's line, three boxes, the open box's detail

    private func lane<T: View>(_ name: String, sub: String, tint: Color, key: String, h: CGFloat, boxes: [PosIntel.Box]?, empty: String?,
                               @ViewBuilder track: @escaping (CGFloat) -> T) -> some View {
        let open = boxes?.first { box == "\(key)|\($0.id)" }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).sType(PT.t(15, 20, 600), tabular: false).foregroundStyle(PC.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(sub).sType(PT.t(12, 16), tabular: false).foregroundStyle(PC.mu).multilineTextAlignment(.trailing)
            }
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    track(g.size.width)
                    Rectangle().fill(PC.today).frame(width: 1.5, height: key == "iv" ? h - 34 : h)
                        .offset(x: CGFloat(fr(m.S)) * g.size.width - 0.75, y: key == "iv" ? 14 : 0)
                }
            }
            .frame(height: h)
            .accessibilityHidden(true)
            if let boxes, !boxes.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(boxes) { q in boxView(q, key: key) }
                }
                .fixedSize(horizontal: false, vertical: true)
                if let q = open, let d = q.detail {
                    detail(d, key: key)
                        .transition(reduce ? .identity : .opacity.combined(with: .move(edge: .top)))
                }
            } else if let empty {
                Text(empty).sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.quiet)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
        .background(tint)
        .overlay(alignment: .top) { Rectangle().fill(PC.rule).frame(height: 1) }
        .animation(S.moving(S.standard(0.35), reduce), value: open?.id)
    }

    private func boxView(_ q: PosIntel.Box, key: String) -> some View {
        let id = "\(key)|\(q.id)", on = box == id
        let content = VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if let ic = q.icon {
                    WallGlyph(kind: ic == .ceiling ? .ceiling : ic == .floor ? .floor : .flip, size: 12)
                        .foregroundStyle(ic == .ceiling ? PC.ceiling : ic == .floor ? PC.floor : PC.orange)
                } else if let d = q.dot {
                    Circle().fill(PC.of(d)).frame(width: 6, height: 6)
                }
                Text(q.label).sType(PT.t(11, 14), tabular: false).foregroundStyle(PC.mu).lineLimit(1)
            }
            Text(q.value).sType(PT.t(16, 20, 600)).foregroundStyle(PC.of(q.valueTone)).lineLimit(1).minimumScaleFactor(0.75)
            if !q.sub.isEmpty {
                Text(q.subMoney && privacy ? BriefMask.mask(q.sub) : q.sub).sType(PT.t(11, 14), tabular: false).foregroundStyle(PC.of(q.subTone))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .topLeading)
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? PC.boxRingOn : PC.boxRing, lineWidth: on ? 1.5 : 1) }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        let said = PosSay.words("\(q.label), \(q.value)" + (q.sub.isEmpty ? "" : ", " + (q.subMoney && privacy ? BriefMask.mask(q.sub) : q.sub)))
        return Group {
            if q.detail != nil {
                Button { box = on ? nil : id } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityLabel(said)
                    .accessibilityValue(on ? "Detail open" : "")
                    .accessibilityHint(on ? "Closes the detail" : "Opens the detail")
            } else {
                content.accessibilityElement(children: .ignore).accessibilityLabel(said)
            }
        }
    }

    private func detail(_ d: PosIntel.Detail, key: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(PC.of(d.dot)).frame(width: 8, height: 8)
                Text(d.title).sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.muT)
                Spacer(minLength: 8)
                Text(d.value).sType(PT.t(17, 22, 600)).foregroundStyle(PC.ink)
                Button { box = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(PC.muT)
                        .frame(width: 26, height: 26).background(Circle().fill(PC.closeFill))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -12).padding(.trailing, -14).padding(.leading, -4)
                .accessibilityLabel("Close")
            }
            VStack(spacing: 4) {
                Rectangle().fill(PC.rule).frame(height: 1).padding(.bottom, 4)
                ForEach(d.rows) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(r.l).sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.mu)
                        Spacer(minLength: 8)
                        Text(r.money && privacy ? BriefMask.shown : r.v).sType(PT.t(13, 18, 500), tabular: false).foregroundStyle(PC.of(r.tone)).lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(PosSay.words("\(r.l), \(r.money && privacy ? "hidden" : r.v)"))
                }
            }
            Text(d.say).sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.say).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PC.detailFill).shadow(color: .black.opacity(0.35), radius: 12, y: 8))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PC.detailEdge, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(PosSay.words("\(d.title), \(d.value)"))
    }

    // MARK: Drawing helpers

    private func vline(_ x: CGFloat, _ top: CGFloat, _ bottom: CGFloat, _ c: Color, _ w: CGFloat = 1.5, dash: [CGFloat] = []) -> some View {
        Path { p in p.move(to: CGPoint(x: x, y: top)); p.addLine(to: CGPoint(x: x, y: bottom)) }
            .stroke(c, style: StrokeStyle(lineWidth: w, dash: dash))
    }
    private func quiet(_ s: String, _ h: CGFloat) -> some View {
        Text(s).sType(PT.t(13, 18), tabular: false).foregroundStyle(PC.mu).frame(height: h, alignment: .center)
    }
    /// A level's look today: the colour (yellow when touched), its opacity (.38 idle), closed through (a capsule), the arrow.
    private func look(_ s: PE.LevelState, _ base: Color) -> (c: Color, o: Double, closed: Bool, ar: String) {
        (s == .touch ? PC.touched : base, s == .idle ? 0.38 : 1, s == .up || s == .dn, s == .up ? "↑ " : s == .dn ? "↓ " : "")
    }
    /// A touched or closed level's mark across the lane: a soft yellow glow and line, or a white line.
    @ViewBuilder private func alertLine(_ x: CGFloat, _ s: PE.LevelState, _ h: CGFloat) -> some View {
        if s != .idle {
            if s == .touch {
                Circle().fill(RadialGradient(colors: [PC.touchedBright.opacity(0.32), PC.touchedBright.opacity(0)], center: .center, startRadius: 0, endRadius: 24))
                    .frame(width: 48, height: 48).offset(x: x - 24, y: h / 2 - 24)
            }
            vline(x, -4, h + 4, s == .touch ? PC.touched.opacity(0.8) : PC.ink.opacity(0.9))
        }
    }
    private func chip(_ s: String, closed: Bool, color: Color, size: CGFloat = 11, weight: CGFloat = 700) -> some View {
        Text(s).sType(PT.t(size, 14, weight)).foregroundStyle(closed ? PC.onInk : color).lineLimit(1).fixedSize()
            .padding(.horizontal, closed ? 6 : 0)
            .background { if closed { Capsule().fill(PC.ink) } }
    }

    // MARK: IV: the chain's mid IV per strike, brighter is richer, a 1 SD bracket

    private func ivAt(_ k: Double) -> Double? {
        let p = m.ivK
        guard p.count >= 2, k >= p[0].K, k <= p[p.count - 1].K else { return nil }
        var i = 1
        while i < p.count - 1 && p[i].K < k { i += 1 }
        let (k0, v0) = p[i - 1], (k1, v1) = p[i]
        return k1 > k0 ? v0 + (v1 - v0) * (k - k0) / (k1 - k0) : v0
    }
    @ViewBuilder private func ivTrack(_ tw: CGFloat) -> some View {
        let stp = PE.stepOf(m.S), SP = stp * (sc.W / stp > 60 ? (sc.W / stp / 60).rounded(.up) : 1)
        let cells: [(k: Double, v: Double)] = {
            var o: [(Double, Double)] = []
            var k = (sc.X0 / SP).rounded(.up) * SP
            while k <= sc.X0 + sc.W + 1e-9 { let kk = Double(PE.num(k, 2)) ?? k; if let v = ivAt(kk) { o.append((kk, v)) }; k += SP }
            return o
        }()
        if cells.count >= 2 {
            let vmn = cells.map(\.v).min()!, vmx = cells.map(\.v).max()!, rr = { (v: Double) in vmx > vmn ? (v - vmn) / (vmx - vmn) : 0.5 }
            let labels = cells.count >= 3 ? [0.12, 0.5, 0.88].map { f in cells.min { abs(fr($0.k) - f) < abs(fr($1.k) - f) }! } : []
            let lo1 = PE.atSd(m.S, -1, m.m), hi1 = PE.atSd(m.S, 1, m.m)
            let bt = "1 SD · \(PE.f2(lo1)) to \(PE.f2(hi1))"
            ForEach(Array(labels.enumerated()), id: \.offset) { _, c in
                let s = String(format: "%.1f", c.v * 100) + "%"
                Text(s).sType(PT.t(11, 14)).foregroundStyle(PC.muT).fixedSize().offset(x: Self.at(fr(c.k), Self.tx(s, 11), tw))
            }
            ZStack(alignment: .topLeading) {
                ForEach(cells, id: \.k) { c in
                    Rectangle().fill(PC.iv(rr(c.v)))
                        .overlay(alignment: .trailing) { Rectangle().fill(PC.page.opacity(0.9)).frame(width: 1) }
                        .frame(width: max(1, CGFloat(SP / sc.W) * tw), height: 26)
                        .offset(x: CGFloat(fr(c.k - SP / 2)) * tw)
                }
            }
            .frame(width: tw, height: 26, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .offset(y: 18)
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                .stroke(PC.ivBracket, lineWidth: 1.5)
                .mask(Rectangle().padding(.top, 1.5))
                .frame(width: max(2, CGFloat(cl01(hi1) - cl01(lo1)) * tw), height: 6)
                .offset(x: CGFloat(cl01(lo1)) * tw, y: 46.5)
            Text(bt).sType(PT.t(11, 14, 600)).foregroundStyle(PC.ivLabel).fixedSize()
                .offset(x: Self.at(cl01(lo1), Self.tx(bt, 11), tw, share: 0.1), y: 57)
        } else {
            quiet("No IV by strike for \(m.label) yet.", 76)
        }
    }

    // MARK: SD: bands at 0.25 to 2 SD in the ramp

    private func sdTrack(_ tw: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(PE.LV.enumerated().reversed()), id: \.offset) { i, k in
                let a = cl01(PE.atSd(m.S, -k, m.m)), b = cl01(PE.atSd(m.S, k, m.m))
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(PC.ramp[i])
                    .frame(width: max(0, CGFloat(b - a) * tw), height: 24).offset(x: CGFloat(a) * tw, y: 2)
            }
        }
        .frame(width: tw, height: 28, alignment: .topLeading)
        .clipped()
    }

    // MARK: Gamma Exposure: ceiling ⇥, floor ⇤, accelerator «, flip ◐, sized by gamma; sold strikes ringed

    @ViewBuilder private func gammaTrack(_ tw: CGFloat) -> some View {
        let ce = m.lv.wall("ceiling"), fl = m.lv.wall("floor"), ac = m.lv.wall("accelerator"), flip = m.lv.flip
        if !m.lv.walls.isEmpty || flip != nil {
            let gmx = max(1, m.lv.walls.map(\.gex).max() ?? 1), isz = { (g: Double) in CGFloat((16 + 12 * g / gmx).rounded()) }
            ForEach([ce, fl, ac].compactMap { $0 }.filter { inSc($0.K) }, id: \.kind) { w in alertLine(CGFloat(fr(w.K)) * tw, m.state(w.K), 84) }
            if let flip, inSc(flip) { alertLine(CGFloat(fr(flip)) * tw, m.state(flip), 84) }
            ForEach([ce, fl].compactMap { $0 }.filter { inSc($0.K) }, id: \.kind) { w in
                let s = m.state(w.K), L = look(s, w.kind == "ceiling" ? PC.ceiling : PC.floor), sz = isz(w.gex), x = CGFloat(fr(w.K)) * tw
                let lab = L.ar + PE.num(w.K, 2), lw = Self.tx(lab, 11) + (L.closed ? 12 : 0)
                Group {
                    WallGlyph(kind: w.kind == "ceiling" ? .ceiling : .floor, size: sz).foregroundStyle(L.c).offset(x: x - sz / 2)
                    chip(lab, closed: L.closed, color: L.c).offset(x: Self.at(fr(w.K), lw, tw), y: sz + 2)
                }
                .opacity(L.o)
            }
            if let flip, inSc(flip) {
                let s = m.state(flip), L = look(s, PC.orange), f = fr(flip), lab = L.ar + PE.f2(flip), lw = Self.tx(lab, 11) + (L.closed ? 12 : 0)
                let right = CGFloat(f) * tw + 12 + lw <= tw
                Group {
                    WallGlyph(kind: .flip, size: 16).foregroundStyle(L.c).offset(x: CGFloat(f) * tw - 8, y: 50)
                    chip(lab, closed: L.closed, color: L.c, weight: 600).offset(x: right ? CGFloat(f) * tw + 11 : max(0, CGFloat(f) * tw - 11 - lw), y: 51)
                }
                .opacity(L.o)
            }
            if let ac, inSc(ac.K) {
                let s = m.state(ac.K), L = look(s, PC.muT), near = flip.map { abs(fr(ac.K) - fr($0)) < 0.08 } ?? false, top: CGFloat = near ? 66 : 50
                let x = CGFloat(fr(ac.K)) * tw, lab = L.ar + PE.num(ac.K, 2), lw = Self.tx(lab, 11) + (L.closed ? 12 : 0)
                Group {
                    WallGlyph(kind: .accelerator, size: 16).foregroundStyle(L.c).offset(x: x - 8, y: top)
                    chip(lab, closed: L.closed, color: L.c, weight: 600).offset(x: max(0, x - 11 - lw), y: top + 1)
                }
                .opacity(L.o)
            }
            ForEach(Array(m.held.filter { inSc($0.K) }.enumerated()), id: \.offset) { _, l in
                Circle().fill(PC.page).overlay(Circle().strokeBorder(PC.ink, lineWidth: 2)).frame(width: 10, height: 10)
                    .offset(x: CGFloat(fr(l.K)) * tw - 5, y: 72)
            }
        } else {
            quiet("No gamma walls for \(m.label) yet.", 84)
        }
    }

    // MARK: Technicals: zones (support filled, resistance hatched), the 20/50/100/200-day as thresholds

    @ViewBuilder private func techTrack(_ tw: CGFloat) -> some View {
        if m.hasTech {
            let zones = m.lv.zones.filter { fr($0.hi) >= 0 && fr($0.lo) <= 1 }
            let zmx = max(1, zones.map(\.strength).max() ?? 1)
            // Zone labels, the nearest to today first; one that would run into a placed label is left to its box.
            let zLab: [Int: CGFloat] = {
                var placed: [(CGFloat, CGFloat)] = [], out: [Int: CGFloat] = [:]
                for (i, z) in zones.enumerated().sorted(by: { abs($0.element.mid - m.S) < abs($1.element.mid - m.S) }) {
                    let s = m.state(z.mid), closed = s == .up || s == .dn
                    let w = Self.tx((closed ? "↑ " : "") + PE.f2(z.mid), 11) + (closed ? 12 : 0), l = Self.at(cl01(z.mid), w, tw)
                    if placed.contains(where: { l < $0.1 + 6 && l + w > $0.0 - 6 }) { continue }
                    placed.append((l, l + w)); out[i] = l
                }
                return out
            }()
            let MAs: [(Int, Double?, Double, CGFloat)] = [(20, m.lv.pe.sma20, 0.45, 600), (50, m.lv.pe.sma50, 0.6, 700), (100, m.lv.pe.sma100, 0.75, 700), (200, m.lv.pe.sma200, 0.9, 800)]
            ForEach(Array(zones.enumerated()), id: \.offset) { _, z in alertLine(CGFloat(fr(z.mid)) * tw, m.state(z.mid), 84) }
            ForEach(MAs.filter { inSc($0.1) }, id: \.0) { a in alertLine(CGFloat(fr(a.1!)) * tw, m.state(a.1!), 84) }
            ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                let s = m.state(z.mid), L = look(s, PC.teal), hold = z.kind == "support", a = 0.35 + 0.5 * (z.strength / zmx)
                let col = s == .touch ? PC.touchedBright : PC.teal
                let w = max(18, CGFloat(cl01(z.hi) - cl01(z.lo)) * tw), x = CGFloat(cl01(z.mid)) * tw
                Group {
                    Group {
                        if hold { RoundedRectangle(cornerRadius: 5, style: .continuous).fill(col.opacity(a)) }
                        else {
                            PosHatch(color: col.opacity(a)).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(col.opacity(0.8), lineWidth: 1.5))
                        }
                    }
                    .frame(width: w, height: 18).offset(x: max(0, min(tw - w, x - w / 2)))
                    if let l = zLab[i] {
                        chip(L.ar + PE.f2(z.mid), closed: L.closed, color: s == .touch ? PC.touched : PC.ink, weight: 600).offset(x: l, y: 20)
                    }
                }
                .opacity(L.o)
            }
            Rectangle().fill(PC.faint).frame(width: tw, height: 1).offset(y: 38)
            ForEach(Array(MAs.enumerated()), id: \.offset) { i, a in
                if let x = a.1 {
                    let s = m.state(x), L = look(s, PC.teal), hold = x < m.S, f = cl01(x), inL = f < 0.1
                    let col = s == .touch ? PC.touchedBright : PC.teal
                    let lab = L.ar + "\(a.0)", lw = Self.tx(lab, 10)
                    Group {
                        Group {
                            if hold { UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3).fill(col.opacity(a.2)) }
                            else {
                                PosHatch(color: col.opacity(a.2)).clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3))
                                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3).strokeBorder(col.opacity(a.2), lineWidth: 1))
                            }
                        }
                        .frame(width: max(0, tw - CGFloat(f) * tw), height: 6).offset(x: CGFloat(f) * tw, y: 44 + CGFloat(i) * 10)
                        Text(lab).font(.inter(10, a.3, tabular: true)).lineLimit(1).fixedSize()
                            .foregroundStyle(L.closed ? PC.onInk : s == .touch ? (inL && hold ? Color.black.opacity(0.85) : PC.touched) : inL && hold ? PC.page : PC.tealLabel)
                            .padding(.horizontal, L.closed ? 4 : 0)
                            .background { if L.closed { Capsule().fill(PC.ink) } }
                            .frame(height: 10)
                            .offset(x: inL ? CGFloat(f) * tw + 4 : max(0, CGFloat(f) * tw - 5 - lw), y: 42 + CGFloat(i) * 10)
                    }
                    .opacity(L.o)
                }
            }
        } else {
            quiet("No technicals for \(m.t) yet.", 84)
        }
    }

    // MARK: Move: last week, this week so far, the 5-day pace carried to the expiry

    @ViewBuilder private func moveTrack(_ tw: CGFloat) -> some View {
        if let mo = m.move, mo.lw != nil || mo.tw != nil || mo.pace != nil {
            ForEach(Array(arrows(mo).enumerated()), id: \.offset) { _, a in
                let x1 = CGFloat(cl01(a.a)) * tw, x2 = CGFloat(cl01(a.b)) * tw, up = a.b >= a.a
                if let rg = a.rg {
                    Capsule().fill(PC.rangeBar).frame(width: max(0, CGFloat(cl01(rg.1) - cl01(rg.0)) * tw), height: 6).offset(x: CGFloat(cl01(rg.0)) * tw, y: a.y + 3)
                }
                Path { p in p.move(to: CGPoint(x: min(x1, x2), y: a.y + 6)); p.addLine(to: CGPoint(x: max(x1, x2), y: a.y + 6)) }
                    .stroke(a.c, style: StrokeStyle(lineWidth: 2, dash: a.dash ? [4, 3] : []))
                Path { p in
                    let tip = CGPoint(x: x2, y: a.y + 6), back = up ? x2 - 6 : x2 + 6
                    p.move(to: tip); p.addLine(to: CGPoint(x: back, y: a.y + 2)); p.addLine(to: CGPoint(x: back, y: a.y + 10)); p.closeSubpath()
                }
                .fill(a.c)
            }
        } else {
            quiet("No recent closes for \(m.t) yet.", 36)
        }
    }

    struct Arrow { let y: CGFloat; let a: Double; let b: Double; let c: Color; let dash: Bool; let rg: (Double, Double)? }
    /// Last week (Fri to Fri closes, with the range behind it), this week so far, and the 5-day pace (dashed).
    private func arrows(_ mo: PE.Move) -> [Arrow] {
        var o: [Arrow] = []
        if let lw = mo.lw { o.append(Arrow(y: 0, a: lw.from, b: lw.to, c: PC.muT, dash: false, rg: (lw.lo, lw.hi))) }
        if let tw = mo.tw { o.append(Arrow(y: 12, a: tw.from, b: m.S, c: PC.ink, dash: false, rg: nil)) }
        if let p = mo.pace { o.append(Arrow(y: 24, a: m.S, b: p.to, c: p.flat ? PC.muT : p.r5 < 0 ? PC.red : PC.green, dash: true, rg: nil)) }
        return o
    }

    // MARK: Held: the profit zone in the SD colours of its breakevens, red where it loses, strikes ringed

    private func heldTrack(_ tw: CGFloat) -> some View {
        heldMarks(tw).frame(width: tw, height: 28, alignment: .topLeading).clipped()
    }
    @ViewBuilder private func heldMarks(_ tw: CGFloat) -> some View {
        let L = m.LH
        if L.has {
            Rectangle().fill(PC.lossLine).frame(width: tw, height: 2).offset(y: 13)
            if !L.none {
                let zl = L.dn == nil ? 0 : cl01(L.dn!), zr = L.up == nil ? 1 : cl01(L.up!)
                let sp = zr > zl ? max(0, min(1, (fr(m.S) - zl) / (zr - zl))) : 0.5
                let cDn = PC.ramp[PE.sdLevel(L.dn == nil ? 2 : abs(PE.zOf(L.dn!, m.S, m.m)))], cUp = PC.ramp[PE.sdLevel(L.up == nil ? 2 : abs(PE.zOf(L.up!, m.S, m.m)))]
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(stops: [.init(color: cDn, location: 0), .init(color: cDn, location: sp), .init(color: cUp, location: sp), .init(color: cUp, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(PC.ink.opacity(0.85), lineWidth: 1.5))
                    .frame(width: max(2, CGFloat(zr - zl) * tw), height: 14).offset(x: CGFloat(zl) * tw, y: 7)
            }
            if let ca = L.callsAlone, let pa = L.putsAlone {
                ForEach([ca, pa].filter { inSc($0) }, id: \.self) { x in vline(CGFloat(fr(x)) * tw, 3, 25, PC.ink.opacity(0.6), 1.5, dash: [3, 2.5]) }
            }
            ForEach([L.dn, L.up].compactMap { $0 }.filter { inSc($0) }, id: \.self) { x in
                Rectangle().fill(PC.ink).frame(width: 2, height: 24).offset(x: CGFloat(fr(x)) * tw - 1, y: 2)
            }
            ForEach(L.strikes.filter { inSc($0) }, id: \.self) { k in
                Circle().fill(PC.page).overlay(Circle().strokeBorder(PC.ink, lineWidth: 2)).frame(width: 10, height: 10).offset(x: CGFloat(fr(k)) * tw - 5, y: 9)
            }
        }
    }
}
