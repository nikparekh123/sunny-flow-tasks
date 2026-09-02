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

/* ⚠ THE SWITCH IS GONE, AND SO IS EVERYTHING THAT GUARDED IT. 2026-09-02:
   the old design is deleted, so there is nothing to fall back to and a
   fallback path would only strand him in a blank app. Removed with it:

     Redesign.isActive     a branch with one outcome
     RedesignSession       a persisted flag nothing reads
     the boot-mark guard   it existed to survive a crash by returning to a
                           working app that no longer exists
     SunnyEscape           shake-to-leave, leaving to nowhere
     SunnyWayBack          the same, at the foot of the New page

   The way back is `git checkout ios-ink-final -- ios-app/`. It is a build,
   not a tap, which is the honest cost of deleting the old app. RootView in
   SunnyfiApp.swift now opens onto this after sign-in, onboarding and the
   biometric lock, so the shell finally sits BEHIND the gate rather than
   beside it. */

struct RedesignRoot: View {
    var body: some View {
        SunnyShell()
            .onAppear { SunnyFontAudit.dump(); SunnyFontAudit.leading() }
    }
}
