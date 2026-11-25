//
//  SFocus.swift
//  Sunny
//
//  The focus look (handoff 2026-11-25-focus, Nik 25 Nov 2026: "the colours are too harsh and pop too much; see how
//  Tesla does it; a hero and the rest info; not every value needs attention; keep the bars in colour").
//  The palette itself is in STokens (page #171717, raised #212121, text #F2F2F2, grey #8C8C8C; light page #F2F2F2,
//  card #FAFAFA, text #212121, grey #6E6E6E). This file holds the rules that depend on the element:
//    2.1 No colour on words: text and numbers are never red, green, orange, yellow or blue. Dark: ink at 15 pt and
//        up, grey under 15. Light: ink or grey.
//    2.2 A gain or loss carries a sign: + up, − (U+2212) down, in the neutral colour (`SF.signed`). Not when an
//        arrow or a sign is already there (▲ ▼ ↑ ↓ ↗ ↘ ± + −).
//    2.3 A warning or an action keeps an 8 pt dot, 7 pt before it, vertically centred: red danger, green ready to
//        act (`SDot`, `SF.dot`). Only on words or numbers 20 pt and up, never for orange or watch, never when the
//        value's own arrow says up or down, never inside a coloured pill. Rare.
//    2.4 Colour lives on marks (dots, pills with a word, rings, strike lines, chart lines) and on the bars: calls
//        blue and puts brown stay on fills (bars, legend squares, chart areas); on words and thin lines they go grey.
//        Large red or green fills with no text go #707070 (`SF.fill`), switches "on" too. Kept in colour on Nik's
//        word (25 Nov): the sector heatmap tiles and the Realized P&L bars.
//    2.5 Bold only at 20 pt and up (SType.focus does it for every Inter font; `.heroic` keeps one).
//        Small capital labels become plain words: as written, no tracking, 13 pt 500, grey.
//    2.6 A chip that is on, in a row of three or more on a dark page, is #424242 with ink words (`SF.chipOn`).
//        The one primary action on a screen stays white.
//

import SwiftUI

enum SF {
    /// Text: ink at 15 pt and up, grey under 15 (dark); light the same pair.
    static let ink = S.ink
    static let grey = S.dyn(0x6E6E6E, 0x8C8C8C)
    static func word(_ size: CGFloat) -> Color { size >= 15 ? ink : grey }

    /// The marks' colours (never on words).
    static let red = S.red        // #E82127 dark, #CC0000 light
    static let green = S.green    // #4CBB6C dark, #1C7840 light
    /// A large red or green fill, a progress bar, a switch that is on: neutral grey.
    static let fill = S.dyn(0x707070, 0x707070)
    /// A chip that is on (dark #424242 with ink words; light keeps the ink chip).
    static let chipOn = S.dyn(0x212121, 0x424242)
    static let chipOnInk = S.dyn(0xFAFAFA, 0xF2F2F2)
    /// Calls blue and puts brown, on fills only; on words and thin lines they go grey.
    static let calls = S.dyn(0x3E6AE1, 0x3E6AE1)
    static let puts = S.dyn(0xB5794A, 0xC8946A)
    static let callsWord = S.dyn(0x6E6E6E, 0xBEBEBE)
    static let putsWord = S.dyn(0x8C8C8C, 0x969696)
    /// Chart levels that were teal or cyan: a grey line and a grey label.
    static let levelLine = S.dyn(0x8C8C8C, 0xAAAAAA)
    static let levelLabel = S.dyn(0x6E6E6E, 0xC8C8C8)

    /// "+$800", "−$4.3K", "+29.6%": the sign of `v` before an unsigned figure. Zero and a figure that already
    /// starts with a sign or an arrow stay as they are.
    static func signed(_ v: Double, _ figure: String) -> String {
        guard let c = figure.first, !"+-−▲▼↑↓↗↘±".contains(c) else { return figure }
        return v > 0 ? "+" + figure : v < 0 ? "\u{2212}" + figure : figure
    }

    enum Dot { case danger, act
        var color: Color { self == .danger ? SF.red : SF.green }
    }
    /// The 8 pt dot as inline text, for a dot inside a Text (then a 7 pt gap).
    static func dot(_ k: Dot) -> Text {
        Text(Image(systemName: "circle.fill")).font(.system(size: 8)).foregroundStyle(k.color)
            + Text("\u{2009}\u{2009}").font(.system(size: 8))
    }
}

/// The 8 pt warning dot before a value, 7 pt gap, vertically centred (README §2.3).
struct SDot: View {
    let kind: SF.Dot
    var body: some View {
        Circle().fill(kind.color).frame(width: 8, height: 8).padding(.trailing, 7).accessibilityHidden(true)
    }
}
