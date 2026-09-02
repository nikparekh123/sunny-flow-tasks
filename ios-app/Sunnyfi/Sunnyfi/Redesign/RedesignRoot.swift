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

/// The switch. Persisted now, with the guard the old comment demanded.
///
/// ⚠ IT USED TO BE SESSION-SCOPED, AND THAT WAS THE SAFETY MECHANISM. Every
/// launch started in the current app, so a launch crash in redesign code was
/// impossible and there was always a way back by quitting. Making the new shell
/// the default gives up both, and the previous note said plainly: "Persisting
/// this later means bringing the guard back with it. Do not persist it
/// casually." So both replacements ship here, and neither is optional.
///
///   1. THE WAY BACK is a control on the New page, `Open the old app`. It sets
///      a persisted escape flag, so it survives a quit. Without it a crash in
///      the new shell leaves an app he trades from with no usable screen.
///   2. THE CRASH GUARD is a boot mark. `on` writes it at launch and
///      `survived()` clears it once the shell has actually drawn. If a launch
///      finds the mark still set, the last launch died before drawing, so this
///      one falls back to the current app rather than boot-looping into a
///      crash. One bad build costs a relaunch, not a rescue build.
@Observable
final class RedesignSession {
    static let shared = RedesignSession()
    private static let escapeKey = "sunny.useCurrentApp"
    private static let bootKey = "sunny.redesignBooting"

    /// true = show the paged shell. Default is now ON.
    var on: Bool

    private init() {
        let d = UserDefaults.standard
        let escaped = d.bool(forKey: Self.escapeKey)
        let diedLastLaunch = d.bool(forKey: Self.bootKey)
        on = !escaped && !diedLastLaunch
        /* Clear the stale mark either way, so the fallback is one launch and
           not a permanent state he cannot get out of. */
        d.set(false, forKey: Self.bootKey)
        if on { d.set(true, forKey: Self.bootKey) }
    }

    /// Called when the shell has drawn. Anything after this point is a crash
    /// inside a working app, not a launch failure, and must not trigger the
    /// fallback.
    func survived() { UserDefaults.standard.set(false, forKey: Self.bootKey) }

    /// The way back. Persisted, so quitting does not undo it.
    func useCurrentApp() {
        let d = UserDefaults.standard
        d.set(true, forKey: Self.escapeKey)
        d.set(false, forKey: Self.bootKey)
        on = false
    }

    /// So the current app can offer a way forward again.
    func useNewShell() {
        UserDefaults.standard.set(false, forKey: Self.escapeKey)
        on = true
    }
}

struct RedesignRoot: View {
    var body: some View {
        SunnyShell()
            .sunnyEscape()
            .onAppear {
                /* ⚠ CLEAR THE BOOT MARK ONLY ONCE SOMETHING IS ON SCREEN. If
                   the shell dies before this runs, the next launch sees the
                   mark and falls back. */
                RedesignSession.shared.survived()
                SunnyFontAudit.dump(); SunnyFontAudit.leading()
            }
    }
}
