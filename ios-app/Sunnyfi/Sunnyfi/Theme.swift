//
//  Theme.swift
//  Sunnyfi
//
//  Navi Design System tokens — verbatim port of the values in
//  `reference/sunny.css` (:root) from the design handoff.
//
//  Usage:
//    Color.theme.page          // canvas
//    Color.theme.neon          // accent / KPIs
//    Font.numeric(size: 16)    // DM Mono fallback to SF Mono for now
//

import SwiftUI

// MARK: - Color tokens

extension Color {
    enum theme {
        // Canvas / surfaces
        static let page       = Color(hex: 0x061a10)     // app canvas
        static let page2      = Color(hex: 0x0a2828)     // sticky bars
        static let surface    = Color(hex: 0x0f3333)     // panels
        static let cardSolid  = Color(hex: 0x0e2e2c)
        static let elevated   = Color(hex: 0x1e5a50)
        static let dusk       = Color(hex: 0x325050)

        // Text
        static let fg1 = Color(hex: 0xfaf5f0)            // primary (warm bone)
        static let fg2 = Color(hex: 0xa8c4c0)            // secondary
        static let fg3 = Color(hex: 0x468278)            // muted
        static let fg4 = Color(hex: 0x325050)            // disabled
        static let fg5 = Color(hex: 0x1e5a50)            // near-invisible dividers

        // Semantic
        static let neon         = Color(hex: 0xd2e632)
        static let neonDark     = Color(hex: 0xc8d820)
        static let pos          = Color(hex: 0xa8d4a0)   // sage — gains
        static let neg          = Color(hex: 0xe87060)   // coral — losses
        static let warn         = Color(hex: 0xe0c060)   // amber
        static let borderBright = Color(hex: 0x326e64)

        // Tints
        static let tintNeon  = Color(hex: 0xd2e632, alpha: 0.10)
        static let tintPos   = Color(hex: 0xa8d4a0, alpha: 0.12)
        static let tintNeg   = Color(hex: 0xe87060, alpha: 0.10)
        static let tintWarn  = Color(hex: 0xe0c060, alpha: 0.14)
        static let tintMuted = Color(hex: 0x1e5a50, alpha: 0.20)

        // Hairlines
        static let hair = Color(hex: 0x326e64, alpha: 0.22)
        static let soft = Color(hex: 0x326e64, alpha: 0.45)
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
// Design calls for DM Mono (numbers) + Work Sans (UI). Until we bundle
// those font files via Info.plist UIAppFonts, we use the closest system
// equivalents — SF Mono for monospace, SF Pro for sans (the default).
// Phase 4 will drop the .ttf files into the bundle.

extension Font {
    /// Tabular-figures number font — DM Mono replacement.
    static func numeric(size: CGFloat, weight: Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// UI font — Work Sans replacement.
    static func ui(size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Uppercase micro-label (~9.5pt, tracked).
    static let microLabel = Font.ui(size: 11, weight: .semibold)
}

// MARK: - Radii (Navi tokens)

enum Radius {
    static let sm: CGFloat   = 4
    static let md: CGFloat   = 8
    static let lg: CGFloat   = 10
    static let xl: CGFloat   = 12
    static let pill: CGFloat = 100
}
