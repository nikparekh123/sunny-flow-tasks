//
//  BiometricGate.swift
//  Sunnyfi
//
//  Shown when AppLock.isLocked == true. Auto-prompts for biometric
//  on appear; user can re-trigger with the big button. If biometric
//  fails repeatedly (or isn't enrolled), falls through to the
//  10-digit pincode entry — same flow as initial sign-in.
//

import SwiftUI

struct BiometricGate: View {
    let lock: AppLock
    let auth: AuthStore
    @State private var showPincodeFallback: Bool = false
    @State private var didAutoPrompt: Bool = false

    var body: some View {
        ZStack {
            Color.theme.page.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: lock.biometricKind.icon)
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(Color.theme.neon)

                Text("Sunnyfi is locked")
                    .font(.ui(size: 22, weight: .bold))
                    .foregroundStyle(Color.theme.fg1)

                Text("Unlock with \(lock.biometricKind.label).")
                    .font(.ui(size: 13))
                    .foregroundStyle(Color.theme.fg3)

                Spacer()

                Button {
                    Task { await tryBiometric() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: lock.biometricKind.icon)
                            .font(.system(size: 16, weight: .bold))
                        Text("Unlock")
                            .font(.ui(size: 15, weight: .bold))
                    }
                    .foregroundStyle(Color.theme.onNeon)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.theme.neon))
                }
                .buttonStyle(.pressable)
                .padding(.horizontal, 24)

                Button {
                    showPincodeFallback = true
                } label: {
                    Text("Use 10-digit code instead")
                        .font(.ui(size: 12, weight: .semibold))
                        .foregroundStyle(Color.theme.fg3)
                }
                .padding(.bottom, 30)
            }
            .padding()
        }
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
        .task {
            // Auto-prompt once on first appearance so the user doesn't
            // have to tap to get the system dialog.
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
        if !ok {
            // No-op: button stays available. iOS shows its own error
            // (user cancelled / face not recognized / etc.).
        }
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
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.theme.fg2)
                    .padding(12)
            }
            .padding(.top, 8)
            .padding(.leading, 8)
        }
    }
}
