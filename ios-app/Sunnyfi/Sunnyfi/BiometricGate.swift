//
//  BiometricGate.swift
//  Sunnyfi
//
//  Shown when AppLock.isLocked == true. An empty screen in the app's
//  own ground while the system Face ID prompt runs; Unlock and the
//  10-digit code appear only after a cancelled or failed scan.
//

import SwiftUI

struct BiometricGate: View {
    let lock: AppLock
    let auth: AuthStore
    @State private var showPincodeFallback: Bool = false
    @State private var didAutoPrompt: Bool = false
    /// Set when Face ID was cancelled or failed: only then is anything drawn.
    @State private var failed: Bool = false
    @AppStorage("sunnyfi.theme") private var themePref = "auto"

    /* ⚠ NO LOCK SCREEN, JUST FACE ID (Nik, 27 Sep 2026: "we don't need a full
       screen for Face ID, usually just the top thing that verifies... the full
       screen turns on white in dark mode"). The gate is the app's own ground in
       the app's own theme, empty, while the system's Face ID prompt runs at the
       top. It read white because it followed the old Ink appearance setting,
       not the theme the pages use. Only a cancelled or failed scan draws a way
       back in: Unlock, and the 10-digit code. */
    var body: some View {
        ZStack {
            S.ground.ignoresSafeArea()
            if failed {
                VStack(spacing: 18) {
                    Spacer()
                    Button {
                        Task { await tryBiometric() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: lock.biometricKind.icon)
                                .font(.system(size: 15, weight: .semibold))
                            Text("Unlock").font(S.inter(S.t14, S.wSemiN))
                        }
                        .foregroundStyle(S.ink)
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .background(Capsule().fill(S.wash))
                    }
                    .buttonStyle(.plain)
                    Button {
                        showPincodeFallback = true
                    } label: {
                        Text("Use 10-digit code instead")
                            .font(S.inter(S.t12, S.wMidSmN)).foregroundStyle(S.mute)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 48)
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(SunnyShell.resolveTheme(themePref, now: Date()))
        .task {
            // Face ID straight away: the system prompt is the whole screen.
            if !didAutoPrompt {
                didAutoPrompt = true
                await tryBiometric()
            }
        }
        .fullScreenCover(isPresented: $showPincodeFallback) {
            // Pincode fallback signs out + re-runs sign-in flow. This
            // is the recover-from-stolen-device path: if Face ID fails
            // the user must re-prove with the team code.
            PincodeFallback(auth: auth, lock: lock)
        }
    }

    private func tryBiometric() async {
        let ok = await lock.authenticate()
        withAnimation(.easeOut(duration: 0.2)) { failed = !ok }
    }
}

/// Wraps SignInView with a "back to biometric" header — when the user
/// successfully re-enters the team code, we mark unlocked and resume.
private struct PincodeFallback: View {
    let auth: AuthStore
    let lock: AppLock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            SignInView(auth: auth)
                .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
                .onChange(of: auth.state) { _, newState in
                    if case .signedIn = newState {
                        // Successful re-auth = unlocked.
                        lock.isLocked = false
                        dismiss()
                    }
                }
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Ink.text)
                    .padding(12)
            }
            .padding(.top, 8)
            .padding(.leading, 8)
        }
    }
}
