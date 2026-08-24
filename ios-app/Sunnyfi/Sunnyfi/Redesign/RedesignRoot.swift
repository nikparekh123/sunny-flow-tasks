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
    /// Simulator always shows the redesign, so building it needs no setting.
    /// The phone shows it only when Nik has turned the switch on in Settings,
    /// and that switch defaults OFF, so a rebuild never surprises him.
    static func isActive(userOn: Bool) -> Bool {
        #if targetEnvironment(simulator)
        // Escape hatch for checking the CURRENT app on the simulator:
        // launch with -currentApp.
        return !ProcessInfo.processInfo.arguments.contains("-currentApp")
        #else
        return userOn
        #endif
    }
}

/// The switch. Deliberately NOT persisted.
///
/// ⚠ SESSION-SCOPED IS THE WHOLE SAFETY MECHANISM. Nik's idea, and it is better
/// than the persisted flag it replaced. Every launch starts in the CURRENT app,
/// so the redesign can only ever be reached by deliberately flipping the switch
/// in a running app. Two consequences fall out for free:
///
///   1. There is always a way back. Quit and reopen. No button needed inside a
///      shell that has no Settings screen yet, and no chance of being trapped in
///      a half-built app until a new build rescues him.
///   2. A launch crash in redesign code is impossible, because launch never
///      starts there. The persisted version needed a crash guard reading a
///      "pending" mark to avoid a permanent boot loop. All of that is now dead
///      code that never has to be right.
///
/// Persisting this later means bringing the guard back with it. Do not persist
/// it casually.
@Observable
final class RedesignSession {
    static let shared = RedesignSession()
    var on = false
    private init() {}
}

struct RedesignRoot: View {
    var body: some View {
        SunnyShell()
            .sunnyEscape()
            .onAppear { SunnyFontAudit.dump(); SunnyFontAudit.leading() }
    }
}
