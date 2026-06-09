//
//  Animations.swift
//  Sunnyfi
//
//  Shared SwiftUI Animation tokens that mirror the design's `--ease`
//  and `--ease-out` cubic-bezier curves (per sunny.css). Use these for
//  every state transition so motion feels consistent.
//

import SwiftUI

enum Motion {
    /// Standard ease — `cubic-bezier(.4,0,.2,1)`. Use for state transitions
    /// (active pill moves, segmented indicator slides, sheets, toggles).
    static let standard = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.34)

    /// Decelerate-out — `cubic-bezier(.16,1,.3,1)`. Use for entrances
    /// (content fading in, bars growing in).
    static let easeOut = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.5)

    /// Quick tap feedback (.15s).
    static let press = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.15)

    /// Segmented-control overshoot — `cubic-bezier(.34,1.2,.4,1)`.
    static let overshoot = Animation.timingCurve(0.34, 1.2, 0.4, 1, duration: 0.36)
}
