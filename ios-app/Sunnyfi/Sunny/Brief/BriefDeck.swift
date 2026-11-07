//
//  BriefDeck.swift
//  Sunny
//
//  The deck (block 29, README 5.3): the day card is home base. One alert a moment slides in on top 1.8 s
//  after Home opens (0.9 s after a moment change) from the right with a small tilt (0.62 s, slight
//  overshoot), sits 8 s, then goes back behind the day card (0.5 s). A swipe, a tap, or closing what it opened
//  also sends it back; X dismisses it for the moment; the dots switch cards; it arrives once a moment. The one
//  that loses sits in the deck without sliding in (answer 5). Cards 200 tall, radius 24; with an alert the
//  stack is 240 tall, the back card peeking 8 pt above. Reduce Motion: no slide, the card just comes to the top.
//
//  ⚠ THE DAY CARD IS DRAWN AS SunnyBriefs.dc.html DRAWS IT (rv32, "sky" on the sky ground), on its own
//  340 × 200 grid stretched to the card: the horizon at y 150; the sun's path from 4:00 AM (x 34) to 8:00 PM
//  (x 306), 62 high at the top of the arc, dipping 16 below the horizon for the 4 hours either side; 49 ticks
//  from x 6 to 334, tall (14) at 4:00, 9:30, 4:00 PM and 8:00 PM, the one under the sun 20 and bright, lit
//  (90%) up to now and faint (30%) after. Six skies by the minute: night < 5:00, dawn < 6:40, morning
//  < 11:00, day < 3:50 PM, sunset < 6:00 PM, dusk < 8:00 PM, then night.
//

import SwiftUI

struct BriefDeck: View {
    let moment: Moment
    let doc: BriefDoc?
    var onAlert: (String) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var alertOnTop = false
    @State private var dismissed = false
    /// Each moment's alert arrives once (per app run).
    nonisolated(unsafe) private static var arrived: Set<String> = []

    private var alert: JSONValue { dismissed ? .null : (doc?.alert ?? .null) }

    var body: some View {
        let hasAlert = !alert.isNull
        VStack(spacing: 10) {
            ZStack(alignment: .top) {
                DayCard(moment: moment, caption: doc?.dayCaption, warn: doc?.dayCaptionOrange ?? false)
                    .frame(height: 200)
                    .scaleEffect(hasAlert && alertOnTop ? 0.96 : 1, anchor: .top)
                    .offset(y: hasAlert ? (alertOnTop ? 0 : 16) : 0)
                    .zIndex(alertOnTop ? 0 : 1)
                    .onTapGesture { if alertOnTop { send(back: true) } }
                if hasAlert {
                    AlertCard(alert: alert, moment: moment, close: { withAnimation(S.standard(0.4)) { dismissed = true; alertOnTop = false } })
                        .frame(height: 200)
                        .scaleEffect(alertOnTop ? 1 : 0.96, anchor: .top)
                        .offset(y: alertOnTop ? 16 : 0)
                        .rotationEffect(.degrees(alertOnTop ? 0 : 0))
                        .zIndex(alertOnTop ? 1 : 0)
                        .onTapGesture {
                            if alertOnTop { onAlert(alert["kind"].string ?? ""); send(back: true) } else { bring() }
                        }
                        .gesture(DragGesture(minimumDistance: 20).onEnded { v in if abs(v.translation.width) > 40 { send(back: alertOnTop) } })
                        .transition(.opacity)
                }
            }
            .frame(height: hasAlert ? 216 : 200, alignment: .top)
            .padding(.horizontal, S.margin)
            HStack(spacing: 6) {
                dot(on: !alertOnTop) { send(back: true) }
                if hasAlert { dot(on: alertOnTop) { bring() } }
            }
        }
        .task(id: moment) {
            guard !alert.isNull, !Self.arrived.contains(moment.rawValue) else { return }
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            Self.arrived.insert(moment.rawValue)
            bring()
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            send(back: true)
        }
    }

    private func bring() {
        withAnimation(reduce ? nil : .timingCurve(0.3, 1.25, 0.5, 1, duration: 0.62)) { alertOnTop = true }
    }
    private func send(back: Bool) {
        withAnimation(reduce ? nil : S.standard(0.5)) { alertOnTop = !back }
    }
    private func dot(on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Capsule().fill(on ? S.ink : S.grabber).frame(width: on ? 22 : 8, height: 8)
        }
        .buttonStyle(.plain)
    }
}

/// An alert card: Earnings season and Holiday on white (kicker in caps, title 28/34 bold, sub, a 200 pt
/// watermark of its mark at 6%, X); Aftershock in the deepest blue of the hour with its scan state and an arrow.
private struct AlertCard: View {
    let alert: JSONValue
    let moment: Moment
    let close: () -> Void
    @Environment(BriefState.self) private var brief

    var body: some View {
        let kind = alert["kind"].string ?? ""
        let dark = kind == "aftershock"
        let (title, sub) = texts(kind)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(dark ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x0E2F6B), Color(hex: 0x1A56B4)], startPoint: .top, endPoint: .bottom))
                           : AnyShapeStyle(S.sheetFill))
                // The watermark draws over the card's shape only, so it can never size the card.
                .overlay(alignment: .bottomTrailing) {
                    if let mark = alert["mark"].string {
                        Text(mark).font(.system(size: 200, weight: .heavy)).foregroundStyle((dark ? Color.white : S.ink).opacity(0.06))
                            .lineLimit(1).fixedSize()
                            .offset(x: 24, y: 56)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text((alert["kicker"].string ?? "").uppercased())
                        .font(.system(size: 13, weight: .bold)).tracking(0.78)
                        .foregroundStyle(dark ? .white.opacity(0.85) : S.ink)
                    Spacer()
                    if dark {
                        Text(alert["arrow"].string ?? "→").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    } else {
                        Button(action: close) { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(S.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss")
                    }
                }
                Spacer()
                // Aftershock near the close counts down to the 4:15 PM scan, each second.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(title.replacingOccurrences(of: "{mm:ss}", with: Self.toScan(brief.now())))
                        .font(.system(size: 28, weight: .bold).monospacedDigit()).foregroundStyle(dark ? .white : S.ink)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
                Text(sub).font(.system(size: 13, weight: .medium)).foregroundStyle(dark ? .white.opacity(0.8) : S.ink)
                    .lineLimit(2).padding(.top, 6)
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Minutes and seconds from now to 4:15 PM New York (the scan), never below 0:00.
    static func toScan(_ d: Date) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let c = cal.dateComponents([.hour, .minute, .second], from: d)
        let s = max(0, (16 * 60 + 15) * 60 - ((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// Aftershock has no fixed text: before the close it waits for the 4:15 scan, near the close it counts
    /// down, after the close it reports what the scan found.
    private func texts(_ kind: String) -> (String, String) {
        if kind == "aftershock" {
            let key: String = switch moment { case .last20, .last5: "soon"; case .post: "done"; default: "wait" }
            let s = alert["states"][key].array.compactMap(\.string)
            return (s.first ?? "Aftershock", s.count > 1 ? s[1] : "")
        }
        return (alert["title"].string ?? "", alert["sub"].string ?? "")
    }
}

struct DayCard: View {
    let moment: Moment
    let caption: String?
    let warn: Bool
    @Environment(BriefState.self) private var brief

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let u = Self.minuteNY(brief.now())
            GeometryReader { g in
                let sx = g.size.width / 340, sy = g.size.height / 200
                let sun = CGPoint(x: Self.x(u) * sx, y: Self.y(u) * sy)
                ZStack(alignment: .topLeading) {
                    Self.sky(u)
                    // A soft warm glow round the sun's x on the horizon (night: dimmer).
                    EllipticalGradient(colors: [Color(red: 1, green: 238 / 255, blue: 210 / 255).opacity(0.38), .clear],
                                       center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: 280, height: 110)
                        .position(x: sun.x, y: 150 * sy)
                        .opacity(Self.phase(u) == .night ? 0.3 : 1)
                    Canvas { ctx, _ in
                        func pt(_ v: Double) -> CGPoint { CGPoint(x: Self.x(v) * sx, y: Self.y(v) * sy) }
                        func path(_ a: Double, _ b: Double) -> Path {
                            var p = Path(); let n = max(2, Int(ceil((b - a) / 5)))
                            for i in 0...n { let v = a + (b - a) * Double(i) / Double(n); i == 0 ? p.move(to: pt(v)) : p.addLine(to: pt(v)) }
                            return p
                        }
                        ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: 150 * sy)); $0.addLine(to: CGPoint(x: 340 * sx, y: 150 * sy)) },
                                   with: .color(.white.opacity(0.3)), lineWidth: 1)
                        ctx.stroke(path(Self.d0 - 240, Self.d0), with: .color(.white.opacity(0.22)), lineWidth: 1)
                        ctx.stroke(path(Self.d1, Self.d1 + 240), with: .color(.white.opacity(0.22)), lineWidth: 1)
                        ctx.stroke(path(Self.d0, Self.d1), with: .color(.white.opacity(0.62)), lineWidth: 1)
                        // 49 ticks under the horizon.
                        let bells = [Self.d0, 570, 960, Self.d1].map { Self.x($0) }
                        let sunX = Self.x(u)
                        for i in 0..<49 {
                            let x = 6 + 328 * Double(i) / 48
                            let tall = bells.contains { abs($0 - x) < 3.4 }, head = abs(x - sunX) < 3.42
                            let top = head ? 0.77 : tall ? 0.79 : 0.82, h: Double = head ? 20 : tall ? 14 : 8
                            let o = head ? 1 : x <= sunX ? 0.9 : 0.3
                            ctx.fill(Path(roundedRect: CGRect(x: x * sx - 0.5, y: top * 200 * sy, width: 1, height: h), cornerRadius: 0.5),
                                     with: .color(.white.opacity(o)))
                        }
                    }
                    // The sun and its clock.
                    Circle().fill(.white).frame(width: 9, height: 9)
                        .shadow(color: .white.opacity(0.7), radius: 6)
                        .position(sun)
                    Text(Self.clock(u))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .fixedSize()
                        .position(x: min(max(sun.x, 34), g.size.width - 34), y: sun.y - 17)
                    VStack(spacing: 1) {
                        Text(Self.session(moment)).font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 5) {
                            if warn { Circle().fill(Color(hex: 0xF2A93B)).frame(width: 6, height: 6) }
                            Text(Self.sub(caption, moment)).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: g.size.width)
                    .padding(.top, 18)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: Color(red: 8 / 255, green: 18 / 255, blue: 48 / 255).opacity(0.45), radius: 14, y: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Self.session(moment)), \(Self.sub(caption, moment)). \(Self.clock(u)).")
        }
    }

    // MARK: Geometry on the 340 × 200 grid

    static let d0 = 240.0, d1 = 1200.0          // 4:00 AM and 8:00 PM, minutes since midnight
    static func x(_ u: Double) -> Double {
        if u < d0 { return 34 * max(0, 1 - (d0 - u) / 240) }
        if u > d1 { return 306 + 34 * min(1, (u - d1) / 240) }
        return 34 + 272 * (u - d0) / (d1 - d0)
    }
    static func y(_ u: Double) -> Double {
        if u < d0 { return 150 + 16 * sin(.pi / 2 * min(1, (d0 - u) / 240)) }
        if u > d1 { return 150 + 16 * sin(.pi / 2 * min(1, (u - d1) / 240)) }
        return 150 - 62 * sin(.pi * (u - d0) / (d1 - d0))
    }

    static func minuteNY(_ d: Date) -> Double {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let c = cal.dateComponents([.hour, .minute], from: d)
        return Double((c.hour ?? 12) * 60 + (c.minute ?? 0))
    }
    static func clock(_ u: Double) -> String {
        let h = Int(u) / 60, m = Int(u) % 60, h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12):\(String(format: "%02d", m)) \(h < 12 ? "AM" : "PM")"
    }

    static func session(_ m: Moment) -> String {
        switch m {
        case .futures: "Futures"
        case .pre: "Pre-market"
        case .bell, .open, .last20, .last5: "Market hours"
        case .post: "Post-market"
        case .weekend: "Weekend"
        }
    }
    /// The caption's second line: the content's own words after the session name, else a plain default.
    static func sub(_ caption: String?, _ m: Moment) -> String {
        if let c = caption, !c.isEmpty {
            let parts = c.components(separatedBy: " · ")
            let s = parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : c
            return s.prefix(1).uppercased() + s.dropFirst()
        }
        switch m {
        case .futures: return "Futures trading since 6:00 PM"
        case .pre: return "Opens at 9:30 AM"
        case .bell: return "The bell just rang"
        case .open, .last20, .last5: return "Closes at 4:00 PM"
        case .post: return "After hours until 8:00 PM"
        case .weekend: return "Markets closed"
        }
    }

    // MARK: The six skies (the horizon glow sits at 75%)

    enum Phase { case night, dawn, morning, day, sunset, dusk }
    static func phase(_ u: Double) -> Phase {
        switch u {
        case ..<300: .night
        case ..<400: .dawn
        case ..<660: .morning
        case ..<950: .day
        case ..<1080: .sunset
        case ..<1200: .dusk
        default: .night
        }
    }
    static func sky(_ u: Double) -> LinearGradient {
        func g(_ s: [(UInt32, Double)]) -> LinearGradient {
            LinearGradient(stops: s.map { .init(color: Color(hex: $0.0), location: $0.1) }, startPoint: .top, endPoint: .bottom)
        }
        switch phase(u) {
        case .night: return g([(0x050A1A, 0), (0x0B1735, 0.55), (0x172A52, 0.75), (0x0B1735, 1)])
        case .dawn: return g([(0x0A1631, 0), (0x1B366C, 0.45), (0x46689F, 0.63), (0xD69657, 0.75), (0x46689F, 0.88), (0x1B366C, 1)])
        case .morning: return g([(0x1D4A92, 0), (0x3C72BE, 0.45), (0x7FAEDF, 0.66), (0xE6D2AE, 0.75), (0x7FAEDF, 0.88), (0x3C72BE, 1)])
        case .day: return g([(0x1A56B4, 0), (0x3478CE, 0.48), (0x79AEE6, 0.75), (0x4F8AD6, 1)])
        case .sunset: return g([(0x13244D, 0), (0x284783, 0.42), (0x5D78A8, 0.6), (0xD98A45, 0.71), (0xEFAE5C, 0.75), (0x5D78A8, 0.88), (0x284783, 1)])
        case .dusk: return g([(0x070F26, 0), (0x12244F, 0.5), (0x2A4580, 0.66), (0xA8622B, 0.75), (0x2A4580, 0.88), (0x12244F, 1)])
        }
    }
}
