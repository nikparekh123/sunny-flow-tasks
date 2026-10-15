//
//  STokens.swift
//  Sunny
//
//  The S namespace (handoff 18/19 `tokens.md`, `Sunny UI Kit.dc.html` §01-02).
//  Every colour, size, radius, shadow and curve in the app comes from here;
//  no view carries a hex. Where tokens.md and the UI Kit disagree the UI Kit
//  wins (README, Precedence) and the difference is listed for Niket.
//

import SwiftUI
import UIKit

enum S {

    // MARK: Colour roles, light / dark

    /// One token, two appearances.
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    /// One token with alpha, two appearances.
    static func dynA(_ light: UInt32, _ la: Double, _ dark: UInt32, _ da: Double) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark).withAlphaComponent(da)
                                                       : UIColor(hex: light).withAlphaComponent(la) })
    }

    static let ink        = dyn(0x1D1D1F, 0xF5F5F7)   // text, selected chip fill
    static let muted      = dyn(0x6E6E73, 0x98989D)   // labels, secondary text
    static let paper      = dyn(0xFFFFFF, 0x1C1C1E)   // solid cards
    static let surface    = dyn(0xF1F2F4, 0x2C2C2E)   // fills inside cards, soft panels
    static let line       = dyn(0xE3E5E8, 0x3A3A3C)   // card outline, hairlines
    static let green      = dyn(0x3B873D, 0x65C466)   // gains, up
    static let red        = dyn(0xD63437, 0xEB4B46)   // losses, down; never a minus sign
    static let yellowDeep = dyn(0x996C23, 0xF7CE46)   // breakeven text, near-breakeven dot
    static let yellow     = dyn(0xF7CE46, 0xF7CE46)   // earnings card, breakeven dot, live glow
    static let blue       = dyn(0x366DEB, 0x3A86F7)   // put strike, links
    /// White text and marks on a filled card (Report green, Theta check ink).
    static let onFill     = Color.white

    // Accents (UI Kit §01)
    static let orange       = dyn(0xF2A93B, 0xF2A93B)  // shares, refresh sun
    static let sunDeep      = Color(hex: 0xE8862E)
    static let sunLight     = Color(hex: 0xFFE98F)
    static let yellowTint   = Color(hex: 0xFDF3D1)     // summary box, hot tile
    static let yellowInk    = Color(hex: 0x6B5B2E)     // text on the tint
    static let receiptRule  = Color(hex: 0xCFCCC5)
    static let receiptSlot  = Color(hex: 0x111111)

    // Rank ramp, Performance (UI Kit §01)
    static let rank: [Color] = [0x1F5F21, 0x2E7A30, 0x3B873D, 0x4FA051, 0x65C466].map { Color(hex: $0) }
    static let unrealizedTint = Color(hex: 0xA9E1AA)
    // Performance's summary box (block 20): soft yellow; dark is a dim
    // yellow wash with a yellow heading and light text.
    static let sumBox  = dynA(0xFDF3D1, 1, 0xF7CE46, 0.14)
    static let sumHead = dyn(0x6B5B2E, 0xF7CE46)
    static let sumText = dyn(0x6B5B2E, 0xD9D9DC)

    /// Yield's closing cost: the light top of each bar (block 17).
    static let callsBack = dyn(0xA9E1AA, 0x2F6B33)
    static let putsBack  = dyn(0xA9C2F7, 0x2A4C8F)
    static let loss1 = Color(hex: 0xB22A2D)
    static let loss2 = Color(hex: 0xD63437)
    static let other = Color(hex: 0xB8BCC2)

    // Account chart compare lines (block 02b), as SunnyHomeChart.dc.html
    // draws them: Sold is ink, Bought is blue, Shares orange, Dividends the
    // yellow-deep token (#996C23 / #F7CE46). No new colours.
    static let lineSold      = ink
    static let lineBought    = blue
    static let lineShares    = orange
    static let lineDividends = yellowDeep

    // Account chart furniture, as SunnyHomeChart.dc.html sets it: the dotted
    // zero line, the ring round the scrub dot, and a selected chip.
    static let chartBase = dyn(0xC7C7CC, 0x636366)
    static let chartRing = dyn(0xFFFFFF, 0x000000)
    static let chipOn    = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(hex: 0xF5F5F7) : UIColor(hex: 0x1D1D1F).withAlphaComponent(0.9) })
    static let chipOnInk = dyn(0xFFFFFF, 0x1C1C1E)

    // Deck card tones (block 03). Dark mode keeps the three filled tones, so
    // these do not swap; the frosted cards use S.frost and S.ink.
    static let deckYellow = Color(hex: 0xF7CE46)
    static let deckInk    = Color(hex: 0x1D1D1F)
    static let deckGreen  = Color(hex: 0x3B873D)

    // The receipt desk and paper (UI Kit §27).
    static let desk       = dyn(0xE6E3DC, 0x0A0A0A)
    static let deskInk    = dyn(0x1D1D1F, 0xF5F5F7)
    static let receiptInk = Color(hex: 0x1D1D1F)
    static let receiptNote = Color(hex: 0x5E5E62)
    static let receiptRed = Color(hex: 0xD63437)
    static let receiptMuted = Color(hex: 0x6E6E73)

    // Portfolio and Watchlist heat (block 10): four steps of strength, mixed
    // in oklch as the design does (green/red into the surface, the strong
    // light steps into ink). Measured equal to the gallery swatches.
    static let heatUp   = [dyn(0xD0DFD0, 0x314131), dyn(0xA9C7A8, 0x365535), dyn(0x38793A, 0x3A703A), dyn(0x336334, 0x3B873D)]
    static let heatDown = [dyn(0xF4D2CF, 0x553330), dyn(0xF0ACA6, 0x793733), dyn(0xBE3435, 0xAC3836), dyn(0x983230, 0xD63437)]

    // Positions (handoff 22, SunnyPositions.dc.html): the put tag's pill, the
    // footer rule, strike lines at 45% muted,
    // the gray status dot, and the corner glow tints (28% light, 22% dark).
    static let pTrack    = dynA(0x1D1D1F, 0.06, 0xFFFFFF, 0.10)
    static let pRule     = dynA(0x1D1D1F, 0.08, 0xFFFFFF, 0.10)
    static let pNeutral  = Color(hex: 0x8E8E93)
    static let pStrike   = dynA(0x6E6E73, 0.45, 0x98989D, 0.45)
    static let pGlowSafe = (r: 101.0, g: 196.0, b: 102.0)
    static let pGlowNear = (r: 142.0, g: 142.0, b: 150.0)
    static let pGlowPast = (r: 235.0, g: 75.0, b: 70.0)
    /// Grid lines and soft fills (Yield, Payback, Sold vs Bought, Risk).
    static let pGrid     = dynA(0x1D1D1F, 0.06, 0xFFFFFF, 0.07)

    /// A figure on the chart and its stats: red when below zero, else ink.
    static func lossInk(_ v: Double) -> Color { v < 0 ? red : ink }

    /// Green up, red down, ink when exactly flat (02b: "$0 is ink").
    static func signed(_ v: Double) -> Color { v > 0 ? green : v < 0 ? red : ink }

    /// Frosted solid deck cards (tokens.md, Glass): the opaque fill under the sheen.
    static let frost: [Color] = [dyn(0xFFFFFF, 0x323234), dyn(0xF6F7F8, 0x1F1F21), dyn(0xFAFAFB, 0x28282A)]

    // MARK: Screen and glow

    /// Page background: a soft tinted gradient so glass has something to refract.
    static var screen: LinearGradient {
        LinearGradient(stops: [
            .init(color: dyn(0xEEF2F0, 0x0A0F0C), location: 0),
            .init(color: dyn(0xF1F2F4, 0x000000), location: 0.38),
            .init(color: dyn(0xF3F1EE, 0x0C0A08), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
    /// The phone design's default screen, "aurora": three soft glows fixed
    /// behind the page (Sunny Phone Standalone, screenBg = aurora). Green
    /// top left, blue right, yellow at the bottom; light / dark strength.
    static let auroraGreen  = (color: Color(red: 101/255, green: 196/255, blue: 102/255), light: 0.42, dark: 0.34)
    static let auroraBlue   = (color: Color(red: 115/255, green: 182/255, blue: 249/255), light: 0.38, dark: 0.30)
    static let auroraYellow = (color: Color(red: 247/255, green: 206/255, blue: 70/255), light: 0.32, dark: 0.22)

    /// Live glow (block 24): sun in light, moon in dark.
    static let glowSun  = Color(red: 247/255, green: 206/255, blue: 70/255).opacity(0.45)
    static let glowMoon = Color(red: 196/255, green: 216/255, blue: 250/255).opacity(0.26)

    // MARK: Shape and space

    static let cardWidth: CGFloat = 353       // a card on its own (393 phone)
    static let rowCardWidth: CGFloat = 341    // cards in a snap row, next one peeks
    static let margin: CGFloat = 20
    static let rCard: CGFloat = 20
    /// Trial, Nik 13 Oct 2026: the glance cards (Inventory, Yield, Payback, Sold vs
    /// Bought, Allocation) in the Theta and Delta glass. Set to false to put them
    /// back on the design's solid paper cards (nothing else changes).
    static let glassCards = false   // trial ended 13 Oct 2026: Nik went back to paper
    static let rDeck: CGFloat = 24
    static let rChip: CGFloat = 16
    static let rPanel: CGFloat = 18
    static let rTile: CGFloat = 14
    static let rPill: CGFloat = 12
    static let padCard: CGFloat = 20
    static let padDeck: CGFloat = 22
    static let gapRow: CGFloat = 8
    static let gapInside: CGFloat = 12
    static let gapGroup: CGFloat = 20
    static let hit: CGFloat = 44

    // MARK: Motion (subtle, Apple-like)

    /// cubic-bezier(.22,1,.36,1): moves, slides, swipes, glass pills.
    static func standard(_ d: Double = 0.42) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: d) }
    /// cubic-bezier(.32,.72,0,1): Now and Exp tags, sheets.
    static func sheet(_ d: Double = 0.45) -> Animation { .timingCurve(0.32, 0.72, 0, 1, duration: d) }
    static let tap: Double = 0.18
    static let move: Double = 0.42
    static let count: Double = 0.85
    static let roll: Double = 0.4
    static let stagger: Double = 0.07
    /// Ranges and filters morph the account line (02b): 0.56 s ease in out.
    static let morph: Animation = .easeInOut(duration: 0.56)
    /// cubic-bezier(.34,1.4,.4,1): the Week | Month thumb, a slight overshoot
    /// (update 14 Oct, Week ↔ Month animation).
    static func thumb(_ d: Double = 0.45) -> Animation { .timingCurve(0.34, 1.4, 0.4, 1, duration: d) }
    /// Bar heights shrinking and growing (Week | Month) and morphing (‹ ›).
    static let grow: Double = 0.7
}

// MARK: - Hex helpers (tokens only; views never take a hex)

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}


// MARK: - Hatch (handoff 24, block 14: rolled contracts)

/// S.hatch: the side's hue in 2 pt stripes at -45°, 3 pt gaps of the same hue
/// at 20%. Fills the frame it is given; the same recipe light and dark.
struct SHatch: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.2)))
            let step: CGFloat = 5 * 2.squareRoot()          // 2 pt stripe + 3 pt gap, across the stripe
            var p = Path(), x = -size.height
            while x < size.width + size.height {
                p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            ctx.stroke(p, with: .color(color), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}

extension S {
    static func hatch(_ c: Color) -> SHatch { SHatch(color: c) }
    /// The small hatched square beside a rolled count (7 pt on a bar label, 8 pt in a key).
    static func hatchSwatch(_ c: Color, size: CGFloat) -> some View {
        SHatch(color: c).frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}
