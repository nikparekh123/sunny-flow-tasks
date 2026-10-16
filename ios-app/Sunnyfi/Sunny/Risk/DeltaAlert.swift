//
//  DeltaAlert.swift
//  Sunny
//
//  Handoff 25 (16 Oct 2026), blocks 14b and 16. A name in trouble breathes:
//  orange when thin (under 20% of its LEAP shares, under 30% the week it
//  reports), red when net short. The Delta tile and the Planner's name chip
//  read the same number from the same package (`risk.delta.by[].alert`).
//
//  Breathing runs on Core Animation, not SwiftUI: a repeating SwiftUI pulse
//  inside a glass card held the app near 80% CPU (Planner audit, 14 Oct).
//  Tint 8% to 17% (red 7% to 15%), ring 1 to 1.5 pt, a 16 pt glow at the
//  peak; 3.6 s orange, 2.6 s red, ease in-out. Reduce Motion: still at rest
//  (tint 12%, a 1.5 pt ring, no glow).
//

import SwiftUI
import UIKit

enum DeltaAlert: Equatable {
    case red, orange

    init?(_ api: String?) {
        switch api { case "red": self = .red; case "orange": self = .orange; default: return nil }
    }
    /// The same rule the server uses, for a number the app works out itself.
    init?(pct: Double, earningsWeek: Bool) {
        if pct < 0 { self = .red } else if pct < 20 + (earningsWeek ? 10 : 0) { self = .orange } else { return nil }
    }
    /// Text on or about the name: S.red, or S.orangeDeep.
    var ink: Color { self == .red ? S.red : S.orangeDeep }
    /// The bright hue for tint, ring, glow and dot (both modes).
    var hue: Color { self == .red ? S.breatheRed : S.breatheOrange }
    var period: Double { self == .red ? 2.6 : 3.6 }
    var rank: Int { self == .red ? 0 : 1 }
}

/// The breathing background of a Delta tile: tint, inner ring and outer glow.
struct AlertBreath: UIViewRepresentable {
    let alert: DeltaAlert
    var radius: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduce

    func makeUIView(context: Context) -> BreathView { BreathView() }
    func updateUIView(_ v: BreathView, context: Context) {
        v.configure(hue: UIColor(alert.hue), red: alert == .red, period: alert.period, radius: radius, still: reduce)
    }

    final class BreathView: UIView {
        private let glow = CALayer(), glowMask = CAShapeLayer(), tile = CALayer()
        private var hue = UIColor.orange, red = false, period = 3.6, radius: CGFloat = 14, still = false
        private var key = ""

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            clipsToBounds = false
            layer.addSublayer(glow)
            layer.addSublayer(tile)
            glow.mask = glowMask
            glowMask.fillRule = .evenOdd
            NotificationCenter.default.addObserver(self, selector: #selector(restart),
                                                   name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError() }

        func configure(hue: UIColor, red: Bool, period: Double, radius: CGFloat, still: Bool) {
            let k = "\(hue)|\(red)|\(period)|\(radius)|\(still)"
            guard k != key else { return }
            key = k; self.hue = hue; self.red = red; self.period = period; self.radius = radius; self.still = still
            restart()
        }

        @objc private func restart() {
            tile.removeAllAnimations(); glow.removeAllAnimations()
            setNeedsLayout()
        }

        override func didMoveToWindow() { super.didMoveToWindow(); restart() }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            tile.frame = bounds
            tile.cornerRadius = radius
            tile.cornerCurve = .continuous
            let rest = (tint: red ? 0.07 : 0.08, ring: 1.0, ringA: 0.5)
            let peak = (tint: red ? 0.15 : 0.17, ring: 1.5, ringA: red ? 0.85 : 0.9, glowA: red ? 0.26 : 0.3)
            // The glow is drawn outside the tile only, like a CSS box-shadow.
            glow.frame = bounds
            let shape = UIBezierPath(roundedRect: bounds.insetBy(dx: -2, dy: -2), cornerRadius: radius + 2).cgPath
            glow.shadowPath = shape
            glow.shadowColor = hue.cgColor
            glow.shadowOffset = .zero
            glow.shadowRadius = 8
            let hole = UIBezierPath(rect: bounds.insetBy(dx: -40, dy: -40))
            hole.append(UIBezierPath(roundedRect: bounds, cornerRadius: radius))
            glowMask.path = hole.cgPath
            if still {
                tile.backgroundColor = hue.withAlphaComponent(0.12).cgColor
                tile.borderWidth = 1.5
                tile.borderColor = hue.withAlphaComponent(red ? 0.85 : 0.85).cgColor
                glow.shadowOpacity = 0
                CATransaction.commit()
                return
            }
            tile.backgroundColor = hue.withAlphaComponent(rest.tint).cgColor
            tile.borderWidth = rest.ring
            tile.borderColor = hue.withAlphaComponent(rest.ringA).cgColor
            glow.shadowOpacity = 0
            CATransaction.commit()
            guard bounds.width > 0, tile.animation(forKey: "breathe") == nil else { return }
            let ease = CAMediaTimingFunction(name: .easeInEaseOut)
            func anim(_ path: String, _ from: Any, _ to: Any) -> CABasicAnimation {
                let a = CABasicAnimation(keyPath: path); a.fromValue = from; a.toValue = to; a.timingFunction = ease; return a
            }
            let g = CAAnimationGroup()
            g.animations = [
                anim("backgroundColor", hue.withAlphaComponent(rest.tint).cgColor, hue.withAlphaComponent(peak.tint).cgColor),
                anim("borderWidth", rest.ring, peak.ring),
                anim("borderColor", hue.withAlphaComponent(rest.ringA).cgColor, hue.withAlphaComponent(peak.ringA).cgColor),
            ]
            g.duration = period / 2; g.autoreverses = true; g.repeatCount = .infinity
            tile.add(g, forKey: "breathe")
            let s = anim("shadowOpacity", 0, Float(peak.glowA))
            s.duration = period / 2; s.autoreverses = true; s.repeatCount = .infinity
            glow.add(s, forKey: "breathe")
        }
    }
}

/// The 6 pt corner dot on a Delta tile and a Planner name chip: opacity 1 to
/// 0.45 and back, in step with the tile.
struct BreathDot: UIViewRepresentable {
    let alert: DeltaAlert
    @Environment(\.accessibilityReduceMotion) private var reduce

    func makeUIView(context: Context) -> DotView { DotView() }
    func updateUIView(_ v: DotView, context: Context) { v.configure(hue: UIColor(alert.hue), period: alert.period, still: reduce) }

    final class DotView: UIView {
        private let dot = CALayer()
        private var period = 3.6, still = false, key = ""
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            layer.addSublayer(dot)
            NotificationCenter.default.addObserver(self, selector: #selector(restart),
                                                   name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError() }
        func configure(hue: UIColor, period: Double, still: Bool) {
            dot.backgroundColor = hue.cgColor
            let k = "\(period)|\(still)"
            guard k != key else { return }
            key = k; self.period = period; self.still = still
            restart()
        }
        @objc private func restart() { dot.removeAllAnimations(); setNeedsLayout() }
        override func didMoveToWindow() { super.didMoveToWindow(); restart() }
        override func layoutSubviews() {
            super.layoutSubviews()
            dot.frame = bounds
            dot.cornerRadius = bounds.width / 2
            guard !still, bounds.width > 0, dot.animation(forKey: "breathe") == nil else { return }
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.45
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.duration = period / 2; a.autoreverses = true; a.repeatCount = .infinity
            dot.add(a, forKey: "breathe")
        }
    }
}
