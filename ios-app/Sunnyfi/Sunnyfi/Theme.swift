//
//  Theme.swift
//  Sunnyfi
//
//  Navi Design System tokens. Each token resolves dynamically against
//  the active UITraitCollection — dark values mirror the original
//  `reference/sunny.css`, light values come from `tokens-light.css`
//  (the Navi light-mode source of truth).
//
//  Usage:
//    Color.theme.page          // canvas (adapts)
//    Color.theme.neon          // accent (lime in dark, deep teal in light)
//    Font.numeric(size: 16)
//

import SwiftUI
import UIKit

// MARK: - Dynamic color helper

extension Color {
    /// Build a Color that resolves differently in light vs dark, driven
    /// by the active UITraitCollection. `.preferredColorScheme(...)` on
    /// the root forces the trait, so user choice (Auto/Light/Dark) flows
    /// through automatically.
    static func dyn(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8)  & 0xFF) / 255
        let b = CGFloat( hex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

// MARK: - Color tokens

extension Color {
    enum theme {
        // Canvas / surfaces
        static let page       = Color.dyn(light: UIColor(hex: 0xf2eee5), dark: UIColor(hex: 0x061a10))
        static let page2      = Color.dyn(light: UIColor(hex: 0xe7ece1), dark: UIColor(hex: 0x0a2828))
        static let surface    = Color.dyn(light: UIColor(hex: 0xffffff), dark: UIColor(hex: 0x0f3333))
        // cardSolid: in dark = solid card fill; in light = warm-white tint over paper
        static let cardSolid  = Color.dyn(light: UIColor(hex: 0xffffff, alpha: 0.74), dark: UIColor(hex: 0x0e2e2c))
        static let elevated   = Color.dyn(light: UIColor(hex: 0xffffff), dark: UIColor(hex: 0x1e5a50))
        static let dusk       = Color.dyn(light: UIColor(hex: 0xd7cfc0), dark: UIColor(hex: 0x325050))

        // Text
        static let fg1 = Color.dyn(light: UIColor(hex: 0x18241c), dark: UIColor(hex: 0xfaf5f0))
        static let fg2 = Color.dyn(light: UIColor(hex: 0x45544a), dark: UIColor(hex: 0xa8c4c0))
        static let fg3 = Color.dyn(light: UIColor(hex: 0x586659), dark: UIColor(hex: 0x468278))
        static let fg4 = Color.dyn(light: UIColor(hex: 0x707d74), dark: UIColor(hex: 0x325050))
        static let fg5 = Color.dyn(light: UIColor(hex: 0xc2c7bc), dark: UIColor(hex: 0x1e5a50))
        /// Stat / return-row label ink (`#6C7275`). Slightly cooler than
        /// fg3/fg4; used specifically for the muted "Shares / Avg cost /
        /// Today's return" style labels per Handoff 2 §1. Dark mode
        /// mirrors to the same brightness against the deeper canvas.
        static let labelMuted = Color.dyn(light: UIColor(hex: 0x6C7275), dark: UIColor(hex: 0x9CA0A3))

        // Semantic
        // neon: brand lime in dark, deep teal-green in light (lime is
        // illegible on paper; deep teal AA-passes as text + fill).
        // Ink rebuild: the brand green is retired — the remaining legacy auth/
        // lock/onboarding screens now read this as ink/paper (no hue, Law 1).
        static let neon         = Color.dyn(light: UIColor(hex: 0x121211), dark: UIColor(hex: 0xF5F3ED))
        static let neonDark     = Color.dyn(light: UIColor(hex: 0x000000), dark: UIColor(hex: 0xEBE9E2))
        static let pos          = Color.dyn(light: UIColor(hex: 0x2a7249), dark: UIColor(hex: 0xa8d4a0))
        static let neg          = Color.dyn(light: UIColor(hex: 0xb04a34), dark: UIColor(hex: 0xe87060))
        static let warn         = Color.dyn(light: UIColor(hex: 0x846114), dark: UIColor(hex: 0xe0c060))
        static let borderBright = Color.dyn(light: UIColor(hex: 0xcbd3c6), dark: UIColor(hex: 0x326e64))

        // Brand-pop lime — preserved for small fills only on light
        // (live-dot, cursor, etc.). In dark it's identical to `neon`.
        static let lime         = Color.dyn(light: UIColor(hex: 0xb9d119), dark: UIColor(hex: 0xd2e632))

        // IV-specific CAUTION fill — sRGB approximation of the design
        // spec's oklch(.82 .135 86) amber. Dark mode bumps brightness
        // slightly so the chip reads against the deeper canvas.
        static let ivAmber      = Color.dyn(light: UIColor(hex: 0xe6c14a), dark: UIColor(hex: 0xf0cc55))

        // Ink color for text/glyphs sitting ON a `neon` fill (CTA pills,
        // segmented control thumbs, etc.). In light the neon is deep
        // teal so white reads cleanly; in dark the neon is lime so
        // near-black (#0a1f12) sits over it per the HTML spec.
        static let onNeon       = Color.dyn(light: UIColor.white, dark: UIColor(hex: 0x121211))

        // Source-leg palette — the 5 colors that paint the Performance
        // diverging stacked bar chart, one per source bucket. Shares
        // reuses `neon`; the other 4 carry their own hues so the stacks
        // read at-a-glance. Each adapts: deeper on paper, lighter on
        // dark canvas. (Gold is also re-used elsewhere — small KPI
        // accents — but lives here as the canonical token.)
        static let oi       = Color.dyn(light: UIColor(hex: 0x2f78c0), dark: UIColor(hex: 0x6aa8e0)) // calls sold
        static let earnings = Color.dyn(light: UIColor(hex: 0x6f4fc4), dark: UIColor(hex: 0xa385e0)) // calls bought
        static let gold     = Color.dyn(light: UIColor(hex: 0xc2961f), dark: UIColor(hex: 0xe0c060)) // puts sold
        static let note     = Color.dyn(light: UIColor(hex: 0xb6508a), dark: UIColor(hex: 0xd285b0)) // puts bought

        // Tints — light values resolve against the deep-teal neon;
        // dark values resolve against the lime neon.
        static let tintNeon  = Color.dyn(
            light: UIColor(hex: 0x0c6a4e, alpha: 0.09),
            dark:  UIColor(hex: 0xd2e632, alpha: 0.10))
        static let tintPos   = Color.dyn(
            light: UIColor(hex: 0x2a7249, alpha: 0.10),
            dark:  UIColor(hex: 0xa8d4a0, alpha: 0.12))
        static let tintNeg   = Color.dyn(
            light: UIColor(hex: 0xb04a34, alpha: 0.09),
            dark:  UIColor(hex: 0xe87060, alpha: 0.10))
        static let tintWarn  = Color.dyn(
            light: UIColor(hex: 0x846114, alpha: 0.11),
            dark:  UIColor(hex: 0xe0c060, alpha: 0.14))
        static let tintMuted = Color.dyn(
            light: UIColor(hex: 0x24382e, alpha: 0.05),
            dark:  UIColor(hex: 0x1e5a50, alpha: 0.20))

        // Hairlines
        static let hair = Color.dyn(
            light: UIColor(hex: 0x19372a, alpha: 0.10),
            dark:  UIColor(hex: 0x326e64, alpha: 0.22))
        static let soft = Color.dyn(
            light: UIColor(hex: 0x19372a, alpha: 0.18),
            dark:  UIColor(hex: 0x326e64, alpha: 0.45))
    }

    /// Convenience: signed-value color (gains/losses).
    static func signed(_ v: Double) -> Color {
        v > 0 ? .theme.pos : v < 0 ? .theme.neg : .theme.fg3
    }

    /// Hex initializer — `Color(hex: 0xd2e632)` or with alpha.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Font tokens
//
// Handoff 2 §1 mandates SF Pro for both labels AND numbers — NOT SF
// Mono. The visual cue that numbers align like a monospace comes from
// `tabular-nums` (SwiftUI: `.monospacedDigit()` modifier applied at
// the Text level), not from a different typeface.
//
// Both helpers now return SF Pro (`.default` design). Numeric texts
// that want column alignment should chain `.monospacedDigit()` —
// most app-wide usages already do, and the modifier is a no-op when
// applied to non-numeric text.

extension Font {
    /// SF Pro at the given size/weight. Pair with `.monospacedDigit()`
    /// at the Text level to get tabular figures (Handoff 2 §1).
    static func numeric(size: CGFloat, weight: Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// SF Pro at the given size/weight.
    static func ui(size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Radii (Navi tokens)

enum Radius {
    static let sm: CGFloat   = 4
    static let md: CGFloat   = 8
    static let lg: CGFloat   = 10
    static let xl: CGFloat   = 12
    static let pill: CGFloat = 100
}
