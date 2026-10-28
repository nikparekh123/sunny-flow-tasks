//
//  SunnyTabBar.swift
//  Sunny
//
//  The tab bar, drawn by hand (Nik, 28 Oct 2026). iOS 27 puts the system's
//  search tab inside the bar as a fifth tab, and the design keeps it apart
//  (block 27). Four tabs in a glass capsule, 70 pt each, centred 35 pt left of
//  the middle; the round 62 pt search button 8 pt to its right; both 28 pt from
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
        GeometryReader { g in
            let mid = g.size.width / 2, y = g.size.height - 28 - 31
            bar.position(x: mid - 35, y: y)
            searchButton.position(x: mid + 117 + 31, y: y)
        }
        .ignoresSafeArea()
    }

    private var index: Int { HomeRouter.Tab.bar.firstIndex(of: tab) ?? 0 }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(HomeRouter.Tab.bar, id: \.self) { t in
                Button { pick(t) } label: {
                    VStack(spacing: 1) {
                        SunnyTabIcon(tab: t).frame(width: 24, height: 24)
                        Text(t.title).font(.system(size: 10, weight: .semibold)).tracking(0.1)
                    }
                    .foregroundStyle(t == tab ? S.ink : S.muted)
                    .frame(width: 70, height: 54)
                    .contentShape(.capsule)
                }
                .buttonStyle(SunnyTabPress())
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(t == tab ? [.isSelected] : [])
            }
        }
        .background(alignment: .leading) {
            Capsule().fill(Self.thumb)
                .overlay(Capsule().strokeBorder(Self.thumbEdge, lineWidth: 0.5))
                .frame(width: 70, height: 54)
                .offset(x: CGFloat(index) * 70)
                .animation(reduce ? nil : .timingCurve(0.3, 1.5, 0.5, 1, duration: 0.45), value: index)
        }
        .animation(.easeOut(duration: 0.25), value: tab)
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

    /// The open tab's thumb: white over the glass in light, a soft lift in dark.
    private static let thumb = S.dynA(0xFFFFFF, 0.6, 0xFFFFFF, 0.14)
    private static let thumbEdge = S.dynA(0x000000, 0.04, 0xFFFFFF, 0.10)
}

/// Pressed: the tab or the button grows 8%.
struct SunnyTabPress: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.scaleEffect(c.isPressed ? 1.08 : 1).animation(.easeOut(duration: 0.2), value: c.isPressed)
    }
}

// MARK: - The design's icons (24 pt)

struct SunnyTabIcon: View {
    let tab: HomeRouter.Tab
    var body: some View {
        ZStack(alignment: .topLeading) {
            switch tab {
            case .home: SunnyHouseGlyph()
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
