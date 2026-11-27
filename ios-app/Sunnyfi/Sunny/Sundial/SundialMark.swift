//
//  SundialMark.swift
//  Sunny
//
//  The Sundial tab's mark (handoff 2026-11-27 README §3.2; sundial-mark.js look "moon", Nik picked 209b): a planet,
//  one tilted orbit and a small moon that passes in front of the planet and behind it every 10 s. Where the front
//  half of the orbit and the moon cross the planet, a gap is cut out of the disc so they read in front. Drawn in a
//  24 box: planet r 4.6, orbit rx 10 ry 3.6 tilted −22°, the back half at .45, the front half at .8 (1.3 strokes),
//  the gap 3.4 wide, the moon r 1.8 in front (r 3.3 cut), r 1.3 at .5 behind.
//  One colour from the tab. It moves only while the Sundial tab is open: the motion eases in over 1.6 s, and leaving
//  the tab holds the pose where it stopped. Still under Reduce Motion.
//

import SwiftUI

struct SundialMark: View {
    let live: Bool
    var size: CGFloat = 30
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var clock = MoonClock()

    var body: some View {
        TimelineView(.animation(paused: !live || reduce)) { tl in
            let t = clock.advance(tl.date, live: live && !reduce)
            Canvas { ctx, sz in Self.draw(&ctx, s: sz.width / 24, t: t) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let tilt = -22.0 * .pi / 180
    private static func ell(_ a: Double, _ s: CGFloat) -> CGPoint {
        let x = 10 * cos(a), y = 3.6 * sin(a)
        return CGPoint(x: (12 + x * cos(tilt) - y * sin(tilt)) * s, y: (12 + x * sin(tilt) + y * cos(tilt)) * s)
    }
    /// Half the orbit: the front from 0 to π (the moon is in front while sin a > 0), the back from π to 2π.
    private static func half(front: Bool, _ s: CGFloat) -> Path {
        var p = Path(), a0 = front ? 0.0 : Double.pi
        p.move(to: ell(a0, s))
        for i in 1...48 { p.addLine(to: ell(a0 + Double.pi * Double(i) / 48, s)) }
        return p
    }
    private static func disc(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }

    static func draw(_ ctx: inout GraphicsContext, s: CGFloat, t: Double) {
        let a = 0.6 + t * .pi * 2 / 10, m = ell(a, s), front = sin(a) > 0
        let centre = CGPoint(x: 12 * s, y: 12 * s), frontArc = half(front: true, s)
        // The back half of the orbit, and the moon behind the planet
        var back = ctx; back.opacity = 0.45
        back.stroke(half(front: false, s), with: .foreground, lineWidth: 1.3 * s)
        if !front { var mb = ctx; mb.opacity = 0.5; mb.fill(disc(m, 1.3 * s), with: .foreground) }
        // The planet, with the gaps cut where the front arc and the moon cross it
        ctx.drawLayer { l in
            l.fill(disc(centre, 4.6 * s), with: .foreground)
            l.blendMode = .destinationOut
            l.stroke(frontArc, with: .color(.black), lineWidth: 3.4 * s)
            if front { l.fill(disc(m, 3.3 * s), with: .color(.black)) }
        }
        // The front half of the orbit, then the moon in front
        var fr = ctx; fr.opacity = 0.8
        fr.stroke(frontArc, with: .foreground, style: StrokeStyle(lineWidth: 1.3 * s, lineCap: .round))
        if front { ctx.fill(disc(m, 1.8 * s), with: .foreground) }
    }
}

/// The mark's time, in seconds of motion: it advances only while live, easing in over 1.6 s (smoothstep) each time
/// the tab is picked, and holds where it stopped.
final class MoonClock {
    private var t = 0.0, sp = 0.0, last: Date?
    func advance(_ d: Date, live: Bool) -> Double {
        guard live else { last = nil; return t }
        guard let l = last else { last = d; sp = 0; return t }
        let dt = min(0.05, max(0, d.timeIntervalSince(l)))
        last = d
        sp = min(1, sp + dt / 1.6)
        t += dt * sp * sp * (3 - 2 * sp)
        return t
    }
}
