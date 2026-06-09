//
//  PressableStyle.swift
//  Sunnyfi
//
//  Drop-in ButtonStyle that mimics the design's `:active { scale(.96) }`
//  + `opacity .55` press feedback. Use `.buttonStyle(.pressable)` on any
//  custom button or tappable row to get consistent tactile response.
//

import SwiftUI

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var fadeOpacity: Double = 0.55

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? fadeOpacity : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Standard pressable tap feedback — slight scale + opacity dip.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }

    /// Subtle variant for row taps where scaling would feel wrong.
    static var pressableRow: PressableButtonStyle {
        PressableButtonStyle(scale: 1, fadeOpacity: 0.55)
    }
}
