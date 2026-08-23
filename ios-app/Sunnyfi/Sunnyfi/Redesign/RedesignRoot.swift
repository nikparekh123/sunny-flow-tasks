//
//  RedesignRoot.swift
//  Sunnyfi — the widget redesign, SIMULATOR ONLY
//
//  ── Why this exists and why it is walled off ───────────────────────────────
//  The redesign is a complete rebuild of the app, not a change to a screen, so
//  it will be half-finished for weeks. Nik uses the current app daily to place
//  real trades. Those two facts cannot share one binary: if the new design sat
//  behind a Settings toggle, every rebuild I handed him would also replace his
//  daily driver, and "stable old app, changing new app" would be impossible.
//
//  So the split is by ENVIRONMENT, not by preference:
//
//      simulator  ->  this file, the redesign
//      device     ->  the current app, untouched
//
//  The device branch is `#if targetEnvironment(simulator)` compiled OUT, not a
//  runtime flag, so no setting, no accident and no bad build can put a
//  half-finished redesign on his phone. He does not rebuild his phone at all
//  during this work; the binary already installed keeps running.
//
//  ── The backend is shared, so it is ADDITIVE ONLY ──────────────────────────
//  ⚠ There is one backend and two clients now. Removing a response field broke
//  the installed app the moment it deployed: position-live dropped
//  stance/bearish/supportive/catalyst, that build declares them non-optional,
//  JSONDecoder threw keyNotFound and every live card went blank. New shapes are
//  added ALONGSIDE old ones; old fields come out only when no installed build
//  reads them.
//
//  ── No sign-in here on purpose ─────────────────────────────────────────────
//  The redesign talks to edge functions with the publishable key, exactly as
//  LiveStore does, so it needs no authenticated session. That keeps Nik's
//  access code out of this entirely: I never need to be given a credential to
//  build or verify a screen.
//

import SwiftUI

enum Redesign {
    /// Compiled out on device. There is deliberately no way to turn this on
    /// from a phone.
    static var isActive: Bool {
        #if targetEnvironment(simulator)
        // Escape hatch for checking the CURRENT app on the simulator:
        // launch with -currentApp.
        return !ProcessInfo.processInfo.arguments.contains("-currentApp")
        #else
        return false
        #endif
    }
}

struct RedesignRoot: View {
    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("REDESIGN").font(InkFont.mono(12)).tracking(12 * 0.2)
                    .foregroundStyle(Ink.dim)
                Text("Simulator only.\nThe app on the phone is untouched.")
                    .font(InkFont.display(19))
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Scaffolding is in place and verified end to end: build, "
                   + "install, launch, screenshot. The screens go here next.")
                    .font(InkFont.display(14))
                    .foregroundStyle(Ink.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
    }
}
