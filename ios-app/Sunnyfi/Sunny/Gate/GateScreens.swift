//
//  GateScreens.swift
//  Sunny
//
//  What stands in front of Home: the access-code sign-in, the first-run
//  choices (Face ID, alerts), the lock, and the sunrise loading screen
//  (block 25, "First load"). Behaviour as in the Sunnyfi app; the look is
//  built from the S tokens only.
//

import SwiftUI
import UserNotifications

// MARK: - Sign in

struct SignInScreen: View {
    let auth: AuthStore
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            SBackground()
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text("Sunny").sType(.largeTitle, tabular: false).foregroundStyle(S.ink)
                Text("Enter your 10-digit access code.")
                    .sType(.body, tabular: false).foregroundStyle(S.muted).padding(.top, 8)
                SecureField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.password)
                    .focused($focused)
                    .sType(.sectionTitle)
                    .foregroundStyle(S.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: S.rTile, style: .continuous).fill(S.paper))
                    .overlay(RoundedRectangle(cornerRadius: S.rTile, style: .continuous).strokeBorder(S.line, lineWidth: 1))
                    .padding(.top, 24)
                    .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(10)) }
                if let e = auth.error {
                    Text(e).sType(.note, tabular: false).foregroundStyle(S.red).padding(.top, 10)
                }
                Button {
                    Task { await auth.signIn(code: code) }
                } label: {
                    Text(auth.isSigningIn ? "Signing in" : "Sign in")
                        .sType(.headline, tabular: false)
                        .foregroundStyle(S.paper)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().fill(S.ink))
                }
                .buttonStyle(SPressStyle())
                .disabled(code.count != 10 || auth.isSigningIn)
                .opacity(code.count == 10 ? 1 : 0.4)
                .padding(.top, 20)
                Spacer()
            }
            .padding(.horizontal, S.margin)
        }
        .onAppear { focused = true }
    }
}

// MARK: - First run

/// The two choices the old onboarding asked: unlock with Face ID, and alerts.
struct FirstRunScreen: View {
    let lock: AppLock
    let onDone: () -> Void
    @State private var faceID = false
    @State private var alerts = false

    var body: some View {
        ZStack {
            SBackground()
            VStack(alignment: .leading, spacing: S.gapInside) {
                Spacer()
                Text("Before you start").sType(.largeTitle, tabular: false).foregroundStyle(S.ink)
                SCard {
                    Toggle(isOn: $faceID) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Unlock with Face ID").sType(.cardTitle, tabular: false).foregroundStyle(S.ink)
                            Text("Your book stays private if the phone is left open.")
                                .sType(.note, tabular: false).foregroundStyle(S.muted)
                        }
                    }
                    .tint(S.green)
                    .onChange(of: faceID) { _, on in
                        guard on else { lock.biometricEnabled = false; return }
                        Task {
                            let ok = await lock.authenticate(reason: "Turn on Face ID for Sunny")
                            lock.biometricEnabled = ok
                            if !ok { faceID = false }
                        }
                    }
                }
                SCard {
                    Toggle(isOn: $alerts) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Alerts").sType(.cardTitle, tabular: false).foregroundStyle(S.ink)
                            Text("Earnings, rolls and anything that needs you.")
                                .sType(.note, tabular: false).foregroundStyle(S.muted)
                        }
                    }
                    .tint(S.green)
                    .onChange(of: alerts) { _, on in
                        guard on else { return }
                        Task {
                            let ok = (try? await UNUserNotificationCenter.current()
                                .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                            if ok { PushAppDelegate.registrar.requestSystemRegistration() } else { alerts = false }
                        }
                    }
                }
                Button(action: onDone) {
                    Text("Continue").sType(.headline, tabular: false).foregroundStyle(S.paper)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().fill(S.ink))
                }
                .buttonStyle(SPressStyle())
                .padding(.top, 8)
                Spacer()
            }
            .padding(.horizontal, S.margin)
        }
    }
}

// MARK: - Lock

struct LockScreen: View {
    let lock: AppLock
    var body: some View {
        ZStack {
            SBackground()
            VStack(spacing: 16) {
                Text("Sunny").sType(.largeTitle, tabular: false).foregroundStyle(S.ink)
                Button {
                    Task { _ = await lock.authenticate() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .sType(.headline, tabular: false)
                        .foregroundStyle(S.ink)
                        .padding(.horizontal, 22).frame(height: 48)
                        .glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(SPressStyle())
            }
        }
        // Over Home now: nothing underneath can be touched or read while it shows.
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isModal)
        .task { _ = await lock.authenticate() }
    }
}
