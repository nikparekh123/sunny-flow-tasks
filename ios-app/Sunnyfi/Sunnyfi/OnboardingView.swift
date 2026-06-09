//
//  OnboardingView.swift
//  Sunnyfi
//
//  3-step welcome shown once on first launch after sign-in:
//   1. What is Sunnyfi (one-screen elevator)
//   2. Enable Face ID (recommended, skippable)
//   3. Enable notifications (recommended, skippable — we explain
//      categories before asking iOS for permission)
//
//  Completion marks `AppLock.onboardingDone = true`. Subsequent
//  launches skip straight to the tab root.
//

import SwiftUI

struct OnboardingView: View {
    let lock: AppLock
    let prefs: NotificationPrefs
    let onFinish: () -> Void

    @State private var step: Int = 0

    var body: some View {
        ZStack {
            Color.theme.page.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                content
                Spacer()
                footer
                    .padding(.bottom, 28)
                    .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(AppPrefs.shared.appearance.colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: introCard
        case 1: biometricCard
        default: notificationsCard
        }
    }

    // MARK: - Step 1: Intro

    private var introCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "chart.bar.doc.horizontal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.theme.neon)
            Text("Welcome to Sunnyfi")
                .font(.ui(size: 26, weight: .bold))
                .foregroundStyle(Color.theme.fg1)
            Text("Your covered-call book, hedge cost, and P&L — all in one place. Live data refreshes every 15 minutes during market hours.")
                .font(.ui(size: 14, weight: .medium))
                .foregroundStyle(Color.theme.fg2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
    }

    // MARK: - Step 2: Biometric

    private var biometricCard: some View {
        VStack(spacing: 18) {
            Image(systemName: lock.biometricKind.icon)
                .font(.system(size: 56))
                .foregroundStyle(Color.theme.neon)
            Text("Protect your book")
                .font(.ui(size: 22, weight: .bold))
                .foregroundStyle(Color.theme.fg1)
            Text("Lock Sunnyfi behind \(lock.biometricKind.label) so anyone holding your phone can't browse your positions.")
                .font(.ui(size: 13, weight: .medium))
                .foregroundStyle(Color.theme.fg2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                Task {
                    let ok = await lock.authenticate(reason: "Enable \(lock.biometricKind.label) lock")
                    if ok {
                        lock.biometricEnabled = true
                        // Don't prompt every app-switch — 1 hour grace
                        // window is the right default for personal use.
                        lock.lockTimeout = .oneHour
                    }
                    step += 1
                }
            } label: {
                Text("Enable \(lock.biometricKind.label)")
                    .font(.ui(size: 14, weight: .bold))
                    .foregroundStyle(Color.theme.onNeon)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.theme.neon))
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    // MARK: - Step 3: Notifications

    private var notificationsCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.theme.neon)
            Text("Get pinged on what matters")
                .font(.ui(size: 22, weight: .bold))
                .foregroundStyle(Color.theme.fg1)
            VStack(alignment: .leading, spacing: 8) {
                bullet("Theta cliff entries (21 DTE / 7 DTE)")
                bullet("Short call goes in the money")
                bullet("Position assigned overnight")
                bullet("Earnings day before")
            }
            .padding(.horizontal, 36)
            Text("Macro releases (CPI / FOMC) are off by default — flip on in Settings.")
                .font(.ui(size: 11, weight: .medium))
                .foregroundStyle(Color.theme.fg3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button {
                Task {
                    let status = await prefs.requestPermission()
                    if status == .authorized || status == .provisional {
                        // User said yes → ask iOS for an APNs device token.
                        // PushAppDelegate receives it and uploads to push_devices.
                        PushAppDelegate.registrar.requestSystemRegistration()
                    }
                    finish()
                }
            } label: {
                Text("Allow notifications")
                    .font(.ui(size: 14, weight: .bold))
                    .foregroundStyle(Color.theme.onNeon)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.theme.neon))
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.theme.neon)
            Text(text)
                .font(.ui(size: 12, weight: .medium))
                .foregroundStyle(Color.theme.fg2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Footer (step indicator + skip)

    private var footer: some View {
        HStack(alignment: .center) {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(i == step ? Color.theme.neon : Color.theme.soft)
                        .frame(width: i == step ? 18 : 6, height: 6)
                }
            }
            Spacer()
            if step < 2 {
                Button {
                    step += 1
                } label: {
                    Text(step == 0 ? "Next" : "Not now")
                        .font(.ui(size: 13, weight: .semibold))
                        .foregroundStyle(Color.theme.fg2)
                }
            } else {
                Button {
                    finish()
                } label: {
                    Text("Skip")
                        .font(.ui(size: 13, weight: .semibold))
                        .foregroundStyle(Color.theme.fg3)
                }
            }
        }
    }

    private func finish() {
        lock.onboardingDone = true
        onFinish()
    }
}
