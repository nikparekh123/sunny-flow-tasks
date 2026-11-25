//
//  SunnyTabBar.swift
//  Sunny
//
//  The tab bar, drawn by hand (Nik, 28 Oct 2026). iOS 27 puts the system's
//  search tab inside the bar as a fifth tab, and the design keeps it apart
//  (block 27). Home · Income · Positions in a glass capsule, 70 pt each, centred 36 pt left of
//  the middle; the round 62 pt search button 10 pt to its right; both 28 pt from
//  the bottom of the screen. The open tab sits on a lighter thumb that slides
//  with a little overshoot. Tap Search to open it; press and hold 0.45 s to
//  open it listening.
//

import SwiftUI

struct SunnyTabBar: View {
    let tab: HomeRouter.Tab
    let pick: (HomeRouter.Tab) -> Void
    /// Opens Search; true when it should open listening (press and hold).
    let search: (_ listening: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        // Handoff 2026-11-24 §2.1: Home · Income · Positions, three 70 × 54 tabs in the glass bar (62 high, radius 31,
        // 4 pt padding), the bar centred at 50% − 36 pt; the 62 pt Search circle from 50% + 83 pt (10 right of the
        // bar); both 28 pt from the bottom.
        GeometryReader { g in
            let mid = g.size.width / 2, y = g.size.height - 28 - 31
            bar.position(x: mid - 36, y: y)
            searchButton.position(x: mid + 83 + 31, y: y)
        }
        .ignoresSafeArea()
    }

    static let tabW: CGFloat = 70

    private var index: Int { HomeRouter.Tab.bar.firstIndex(of: tab) ?? 0 }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(HomeRouter.Tab.bar, id: \.self) { t in
                Button { pick(t) } label: {
                    VStack(spacing: 1) {
                        SunnyTabIcon(tab: t).frame(width: 24, height: 24)
                        Text(t.title).font(.inter(11, 600)).tracking(0.11).lineLimit(1).fixedSize()
                    }
                    .foregroundStyle(t == tab ? S.ink : S.secondary)
                    .frame(width: Self.tabW, height: 54)
                    .contentShape(.capsule)
                }
                .buttonStyle(SunnyTabPress())
                .accessibilityLabel(t.title)
                .accessibilityValue("tab \(HomeRouter.Tab.bar.firstIndex(of: t).map { $0 + 1 } ?? 1) of \(HomeRouter.Tab.bar.count)")
                .accessibilityAddTraits(t == tab ? [.isSelected] : [])
            }
        }
        .background(alignment: .leading) {
            // The design's thumb (Current App nav.thBg/thSh): white .6 with a white top edge, a .5 ring and a soft
            // shadow in light (without the shadow it vanished over the light Income page, 25 Nov 2026); white .14 with
            // a .18 top edge in dark.
            Capsule().fill(Self.thumb)
                .overlay(Capsule().strokeBorder(Self.thumbEdge, lineWidth: 0.5))
                .overlay(alignment: .top) {
                    Capsule().stroke(Self.thumbTop, lineWidth: 1).frame(height: 54).mask(alignment: .top) { Rectangle().frame(height: 2) }
                }
                .shadow(color: Self.thumbShadow, radius: 1.5, y: 1)
                .frame(width: Self.tabW, height: 54)
                .offset(x: CGFloat(index) * Self.tabW)
                .animation(S.moving(Self.thumbMove, reduce), value: index)
        }
        .animation(S.fade, value: tab)
        .sensoryFeedback(.selection, trigger: tab)
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }

    private var searchButton: some View {
        // A hold opens Search listening at 0.45 s; the release that follows lands on a Search already open.
        Button { search(false) } label: {
            SunnySearchGlyph().frame(width: 24, height: 24).foregroundStyle(S.ink)
                .frame(width: 62, height: 62).contentShape(.circle)
        }
        .buttonStyle(SunnyTabPress())
        .glassEffect(.regular, in: .circle)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            search(true)
        })
        .accessibilityLabel("Search")
        .accessibilityHint("Press and hold to ask by voice")
        .accessibilityAction(named: "Ask by voice") { search(true) }
    }

    /// The thumb slides 70 pt a tab: .45 s cubic-bezier(.3,1.5,.5,1) (handoff 2026-11-24 §5).
    private static let thumbMove: Animation = .timingCurve(0.3, 1.5, 0.5, 1, duration: 0.45)
    /// The open tab's thumb: white over the glass in light, a soft lift in dark.
    private static let thumb = S.dynA(0xFFFFFF, 0.6, 0xFFFFFF, 0.14)
    private static let thumbEdge = S.dynA(0x000000, 0.04, 0xFFFFFF, 0.10)
    private static let thumbTop = S.dynA(0xFFFFFF, 1, 0xFFFFFF, 0.18)
    private static let thumbShadow = S.dynA(0x000000, 0.10, 0x000000, 0)
}

/// Pressed: the tab or the button grows 8%; under Reduce Motion it dims instead.
struct SunnyTabPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce
    func makeBody(configuration c: Configuration) -> some View {
        c.label.scaleEffect(c.isPressed && !reduce ? 1.08 : 1).opacity(c.isPressed && reduce ? 0.6 : 1)
            .animation(S.fade, value: c.isPressed)
    }
}

// MARK: - The design's icons (24 pt)

struct SunnyTabIcon: View {
    let tab: HomeRouter.Tab
    var body: some View {
        ZStack(alignment: .topLeading) {
            switch tab {
            case .home: SunnyHouseGlyph()
            case .income:
                // A calendar: the header bar at 45%, the body solid, two rings on top.
                part(3, 4.6, 18, 4.4, 2).opacity(0.45)
                part(3, 10.4, 18, 10.8, 2.6)
                part(6.8, 2.4, 2.2, 4.6, 1.1)
                part(15, 2.4, 2.2, 4.6, 1.1)
            case .positions:
                part(8, 2.6, 8, 1.8, 0.9).opacity(0.35)
                part(5.5, 5.6, 13, 2, 1).opacity(0.6)
                part(3, 9, 18, 12, 2.6)
            case .gamma:
                part(4, 2.5, 2.2, 19, 1.1).opacity(0.45)
                part(8, 4, 12.5, 4, 2)
                part(8, 10, 7.5, 4, 2)
                part(8, 16, 10.5, 4, 2)
            case .insights:
                Circle().frame(width: 13.2, height: 13.2).position(x: 12, y: 9)
                part(8.98, 12, 6.04, 5.55, 1)
                part(9, 18.2, 6, 1.8, 0.9)
                part(10, 20.8, 4, 1.6, 0.8)
            case .search: SunnySearchGlyph()
            }
        }
        .frame(width: 24, height: 24, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// A rounded bar at x, y (from the top left of the 24 pt box), w by h.
    private func part(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: r).frame(width: w, height: h).position(x: x + w / 2, y: y + h / 2)
    }
}

struct SunnyHouseGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
        var h = Path()
        h.move(to: p(12, 3.2)); h.addLine(to: p(3, 10.4)); h.addLine(to: p(3, 20))
        h.addQuadCurve(to: p(4.3, 21.3), control: p(3, 21.3))
        h.addLine(to: p(9.5, 21.3)); h.addLine(to: p(9.5, 15.1)); h.addLine(to: p(14.5, 15.1)); h.addLine(to: p(14.5, 21.3))
        h.addLine(to: p(19.7, 21.3)); h.addQuadCurve(to: p(21, 20), control: p(21, 21.3))
        h.addLine(to: p(21, 10.4)); h.closeSubpath()
        return h
    }
}

/// The magnifier: a 6.5 pt ring and its handle, 2.2 pt strokes.
struct SunnySearchGlyph: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size.width / 24
            Path { p in
                p.addEllipse(in: CGRect(x: 4 * s, y: 4 * s, width: 13 * s, height: 13 * s))
                p.move(to: CGPoint(x: 15.5 * s, y: 15.5 * s)); p.addLine(to: CGPoint(x: 20 * s, y: 20 * s))
            }
            .stroke(style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
