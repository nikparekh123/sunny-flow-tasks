//
//  SunnyEscape.swift
//  Sunny — the way back to the current app.
//
//  ⚠ WITHOUT THIS THE SWITCH IS A ONE-WAY DOOR. Turning the redesign on boots
//  straight into the Sunny shell, and that shell has no Settings screen yet, so
//  the control that turned it on is unreachable from inside it. Nothing crashes,
//  so the crash guard never fires. Nik would simply be stuck in a half-built app
//  until a new build rescued him. He spotted this before it shipped.
//
//  Shake to leave. Chosen because it costs the design NOTHING: no button, no
//  gesture layered over a real control, no pixel altered, which matters while
//  the rule is to replicate the handoff exactly. It is also close to impossible
//  to trigger by accident, and a confirmation catches the once-in-a-year case
//  where a pocket manages it.
//
//  This is scaffolding. When the redesign grows its own Settings screen the
//  switch lives there and this file goes.
//

import SwiftUI
import UIKit

struct SunnyEscape: ViewModifier {
    @State private var redesign = RedesignSession.shared
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .background(ShakeDetector { asking = true }.allowsHitTesting(false))
            .confirmationDialog("Leave the new design?", isPresented: $asking, titleVisibility: .visible) {
                Button("Back to the current app") { redesign.on = false }
                Button("Stay", role: .cancel) { }
            } message: {
                Text("Quitting and reopening the app does the same thing.")
            }
    }
}

extension View {
    func sunnyEscape() -> some View { modifier(SunnyEscape()) }
}

/// Shake reaches SwiftUI only through the responder chain, so a UIKit
/// controller has to hold first responder and forward the motion event.
private struct ShakeDetector: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let c = Controller(); c.onShake = onShake; return c
    }
    func updateUIViewController(_ c: Controller, context: Context) { c.onShake = onShake }

    final class Controller: UIViewController {
        var onShake: (() -> Void)?
        override var canBecomeFirstResponder: Bool { true }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }
        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            guard motion == .motionShake else { return }
            onShake?()
        }
    }
}
